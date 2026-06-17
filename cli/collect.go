package main

import (
	"bufio"
	"context"
	"hash/fnv"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// ---- wire types: the snapshot contract the browser consumes ----

type Port struct {
	Port  int    `json:"port"`
	Proto string `json:"proto"` // tcp
	Scope string `json:"scope"` // localhost | all
}

type Child struct {
	PID   int     `json:"pid"`
	Label string  `json:"label"`
	CPU   float64 `json:"cpu"`
	RSSMB float64 `json:"rss_mb"`
	Cmd   string  `json:"cmd"`
}

type Node struct {
	ID      string  `json:"id"`
	Label   string  `json:"label"`
	Kind    string  `json:"kind"` // app | proc
	CPU     float64 `json:"cpu"`
	RSSMB   float64 `json:"rss_mb"`
	PIDs    []int   `json:"pids"`
	Ports   []Port  `json:"ports"`
	Sockets []string `json:"sockets"`
	Cmd     string  `json:"cmd"`
	Kids    []Child `json:"children"`
}

type Edge struct {
	Src    string `json:"src"`
	Dst    string `json:"dst"`
	Kind   string `json:"kind"`   // unix | tcp
	Detail string `json:"detail"` // socket path or addr
}

type Snapshot struct {
	TS    int64  `json:"ts"`
	Nodes []Node `json:"nodes"`
	Edges []Edge `json:"edges"`
	Note  string `json:"note,omitempty"`
}

// ---- internal process model ----

type proc struct {
	pid, ppid int
	cpu       float64
	rssKB     int64
	exe       string // ps comm — full exec path when available
	cmd       string // ps command — full cmdline (redacted before display)
	nodeID    string
	label     string
	kind      string
}

type collector struct {
	minCPU float64
	minMB  float64
}

// nowFn is injected so the package stays free of forbidden Date.now-style calls
// in tests; main supplies time.Now().Unix().
var nowUnix func() int64 = func() int64 { return 0 }

func (c *collector) collect(ctx context.Context) (Snapshot, error) {
	procs, err := readProcs(ctx)
	if err != nil {
		return Snapshot{}, err
	}
	// resolve cmdlines (separate ps so paths-with-spaces don't break parsing)
	cmds, _ := readCmds(ctx)
	for pid, p := range procs {
		if cl, ok := cmds[pid]; ok {
			p.cmd = redact(cl)
		}
	}
	assignNodes(procs)

	ports, unixEP, unixListen, tcpEP := readSockets(ctx)

	nodes := buildNodes(procs, ports, unixListen)
	visible := map[string]bool{}
	kept := filterNodes(nodes, c.minCPU, c.minMB)
	for _, n := range kept {
		visible[n.ID] = true
	}
	edges := buildEdges(procs, unixEP, tcpEP, visible)

	sort.Slice(kept, func(i, j int) bool { return kept[i].CPU > kept[j].CPU })
	return Snapshot{TS: nowUnix(), Nodes: kept, Edges: edges}, nil
}

// ---- ps parsing ----

func readProcs(ctx context.Context) (map[int]*proc, error) {
	out, err := run(ctx, "ps", "-axo", "pid=,ppid=,pcpu=,rss=,comm=")
	if err != nil {
		return nil, err
	}
	m := map[int]*proc{}
	sc := bufio.NewScanner(strings.NewReader(out))
	sc.Buffer(make([]byte, 0, 1<<20), 1<<20)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) < 5 {
			continue
		}
		pid, _ := strconv.Atoi(f[0])
		ppid, _ := strconv.Atoi(f[1])
		cpu, _ := strconv.ParseFloat(f[2], 64)
		rss, _ := strconv.ParseInt(f[3], 10, 64)
		exe := strings.Join(f[4:], " ") // comm is last; rejoin to keep spaced .app paths
		if pid == 0 {
			continue // kernel_task
		}
		m[pid] = &proc{pid: pid, ppid: ppid, cpu: cpu, rssKB: rss, exe: exe}
	}
	return m, sc.Err()
}

func readCmds(ctx context.Context) (map[int]string, error) {
	out, err := run(ctx, "ps", "-axo", "pid=,command=")
	if err != nil {
		return nil, err
	}
	m := map[int]string{}
	sc := bufio.NewScanner(strings.NewReader(out))
	sc.Buffer(make([]byte, 0, 1<<20), 1<<20)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		sp := strings.IndexByte(line, ' ')
		if sp < 0 {
			continue
		}
		pid, _ := strconv.Atoi(line[:sp])
		m[pid] = strings.TrimSpace(line[sp+1:])
	}
	return m, sc.Err()
}

// ---- node identity: first .app in the exec path groups all helpers together ----

func assignNodes(procs map[int]*proc) {
	for _, p := range procs {
		if bundle, name, ok := appBundle(p.exe); ok {
			p.nodeID = "app:" + bundle
			p.label = name
			p.kind = "app"
			continue
		}
		p.kind = "proc"
		p.label = baseName(p.exe)
		// stable across respawn: key on exe+redacted-cmd, never pid
		h := fnv.New32a()
		h.Write([]byte(p.exe))
		h.Write([]byte{0})
		h.Write([]byte(p.cmd))
		p.nodeID = "proc:" + p.label + ":" + strconv.FormatUint(uint64(h.Sum32()), 16)
	}
}

func appBundle(exe string) (bundle, name string, ok bool) {
	i := strings.Index(exe, ".app/")
	if i < 0 {
		if strings.HasSuffix(exe, ".app") {
			return exe, baseName(strings.TrimSuffix(exe, ".app")), true
		}
		return "", "", false
	}
	bundle = exe[:i+4]
	name = baseName(strings.TrimSuffix(bundle, ".app"))
	return bundle, name, true
}

func baseName(p string) string {
	if p == "" {
		return "?"
	}
	b := filepath.Base(p)
	return b
}

// ---- aggregate procs into nodes ----

func buildNodes(procs map[int]*proc, ports map[int][]Port, unixListen map[int][]string) []Node {
	byID := map[string]*Node{}
	order := []string{}
	for _, p := range procs {
		n, ok := byID[p.nodeID]
		if !ok {
			n = &Node{ID: p.nodeID, Label: p.label, Kind: p.kind, Cmd: p.cmd}
			byID[p.nodeID] = n
			order = append(order, p.nodeID)
		}
		n.CPU += p.cpu
		n.RSSMB += float64(p.rssKB) / 1024
		n.PIDs = append(n.PIDs, p.pid)
		n.Kids = append(n.Kids, Child{PID: p.pid, Label: baseName(p.exe), CPU: p.cpu, RSSMB: float64(p.rssKB) / 1024, Cmd: p.cmd})
		n.Ports = append(n.Ports, ports[p.pid]...)
		n.Sockets = append(n.Sockets, unixListen[p.pid]...)
	}
	out := make([]Node, 0, len(order))
	for _, id := range order {
		n := byID[id]
		n.Ports = dedupPorts(n.Ports)
		n.Sockets = dedupStrings(n.Sockets)
		// non-nil slices so the JSON contract is always [] not null
		if n.Ports == nil {
			n.Ports = []Port{}
		}
		if n.Sockets == nil {
			n.Sockets = []string{}
		}
		n.RSSMB = round1(n.RSSMB)
		n.CPU = round1(n.CPU)
		sort.Ints(n.PIDs)
		sort.Slice(n.Kids, func(i, j int) bool { return n.Kids[i].CPU > n.Kids[j].CPU })
		out = append(out, *n)
	}
	return out
}

func filterNodes(nodes []Node, minCPU, minMB float64) []Node {
	out := make([]Node, 0, len(nodes))
	for _, n := range nodes {
		keep := n.CPU >= minCPU || n.RSSMB >= minMB || len(n.Ports) > 0 || len(n.Sockets) > 0
		if keep {
			out = append(out, n)
		}
	}
	return out
}

// ---- edges ----

func buildEdges(procs map[int]*proc, unixEP []unixEndpoint, tcpEP []tcpEndpoint, visible map[string]bool) []Edge {
	pidNode := func(pid int) (string, bool) {
		p, ok := procs[pid]
		if !ok {
			return "", false
		}
		return p.nodeID, true
	}

	seen := map[string]Edge{}
	add := func(a, b, kind, detail string) {
		if a == "" || b == "" || a == b {
			return
		}
		if !visible[a] || !visible[b] {
			return
		}
		// undirected dedup
		x, y := a, b
		if x > y {
			x, y = y, x
		}
		k := kind + "|" + x + "|" + y
		if _, ok := seen[k]; !ok {
			seen[k] = Edge{Src: x, Dst: y, Kind: kind, Detail: detail}
		}
	}

	// unix: match my dev to another endpoint's peer
	devToPID := map[string]int{}
	for _, e := range unixEP {
		devToPID[e.dev] = e.pid
	}
	for _, e := range unixEP {
		if e.peer == "" {
			continue
		}
		peerPID, ok := devToPID[e.peer]
		if !ok {
			continue
		}
		na, oka := pidNode(e.pid)
		nb, okb := pidNode(peerPID)
		if oka && okb {
			add(na, nb, "unix", "unix socket")
		}
	}

	// tcp: pair established endpoints local<->remote
	localToPID := map[string]int{}
	for _, e := range tcpEP {
		if e.state == "ESTABLISHED" && e.local != "" {
			localToPID[e.local] = e.pid
		}
	}
	for _, e := range tcpEP {
		if e.state != "ESTABLISHED" || e.remote == "" {
			continue
		}
		peerPID, ok := localToPID[e.remote]
		if !ok {
			continue
		}
		na, oka := pidNode(e.pid)
		nb, okb := pidNode(peerPID)
		if oka && okb {
			add(na, nb, "tcp", e.local+"→"+e.remote)
		}
	}

	out := make([]Edge, 0, len(seen))
	for _, e := range seen {
		out = append(out, e)
	}
	sort.Slice(out, func(i, j int) bool {
		if out[i].Src != out[j].Src {
			return out[i].Src < out[j].Src
		}
		return out[i].Dst < out[j].Dst
	})
	return out
}

// ---- lsof parsing ----

type unixEndpoint struct {
	pid       int
	dev, peer string
}
type tcpEndpoint struct {
	pid           int
	local, remote string
	state         string
}

func readSockets(ctx context.Context) (ports map[int][]Port, unixEP []unixEndpoint, unixListen map[int][]string, tcpEP []tcpEndpoint) {
	ports = map[int][]Port{}
	unixListen = map[int][]string{}
	out, err := run(ctx, "lsof", "-nP", "-w", "-F", "pctdnPT", "-iTCP", "-U")
	if err != nil {
		return
	}
	sc := bufio.NewScanner(strings.NewReader(out))
	sc.Buffer(make([]byte, 0, 1<<20), 1<<20)

	var curPID int
	// per-file accumulators
	var t, d, n, proto, state string
	flush := func() {
		switch {
		case t == "unix":
			if strings.HasPrefix(n, "->") {
				unixEP = append(unixEP, unixEndpoint{pid: curPID, dev: d, peer: strings.TrimPrefix(n, "->")})
			} else if strings.HasPrefix(n, "/") {
				unixListen[curPID] = append(unixListen[curPID], n)
			}
		case proto == "TCP":
			if state == "LISTEN" {
				if port, scope, ok := parseListen(n); ok {
					ports[curPID] = append(ports[curPID], Port{Port: port, Proto: "tcp", Scope: scope})
				}
			} else if state == "ESTABLISHED" {
				l, r := splitConn(n)
				tcpEP = append(tcpEP, tcpEndpoint{pid: curPID, local: l, remote: r, state: state})
			}
		}
		t, d, n, proto, state = "", "", "", "", ""
	}
	started := false
	for sc.Scan() {
		line := sc.Text()
		if line == "" {
			continue
		}
		switch line[0] {
		case 'p':
			if started {
				flush()
			}
			started = false
			curPID, _ = strconv.Atoi(line[1:])
		case 'f': // new file descriptor — flush previous
			if started {
				flush()
			}
			started = true
		case 't':
			t = line[1:]
		case 'd':
			d = line[1:]
		case 'n':
			n = line[1:]
		case 'P':
			proto = line[1:]
		case 'T':
			if strings.HasPrefix(line[1:], "ST=") {
				state = line[4:]
			}
		}
	}
	if started {
		flush()
	}
	return
}

func parseListen(n string) (port int, scope string, ok bool) {
	// forms: *:8080 | 127.0.0.1:8080 | [::1]:8080 | [::]:8080
	host, p := splitHostPort(n)
	port, err := strconv.Atoi(p)
	if err != nil {
		return 0, "", false
	}
	switch host {
	case "127.0.0.1", "::1", "[::1]", "localhost":
		scope = "localhost"
	case "*", "0.0.0.0", "::", "[::]":
		scope = "all"
	default:
		scope = "all"
	}
	return port, scope, true
}

func splitConn(n string) (local, remote string) {
	i := strings.Index(n, "->")
	if i < 0 {
		return n, ""
	}
	return n[:i], n[i+2:]
}

func splitHostPort(s string) (host, port string) {
	i := strings.LastIndex(s, ":")
	if i < 0 {
		return s, ""
	}
	return s[:i], s[i+1:]
}

// ---- helpers ----

func run(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	out, err := cmd.Output()
	return string(out), err
}

func dedupPorts(in []Port) []Port {
	seen := map[string]bool{}
	out := in[:0]
	for _, p := range in {
		k := p.Proto + ":" + strconv.Itoa(p.Port) + ":" + p.Scope
		if !seen[k] {
			seen[k] = true
			out = append(out, p)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Port < out[j].Port })
	return out
}

func dedupStrings(in []string) []string {
	seen := map[string]bool{}
	out := in[:0]
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	sort.Strings(out)
	return out
}

func round1(f float64) float64 {
	return float64(int64(f*10+0.5)) / 10
}
