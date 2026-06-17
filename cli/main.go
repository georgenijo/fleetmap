package main

import (
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os/exec"
	"sync"
	"time"
)

//go:embed web/index.html
var webFS embed.FS

func main() {
	addr := flag.String("addr", "127.0.0.1:0", "listen address (localhost only by design)")
	interval := flag.Duration("interval", 2*time.Second, "snapshot refresh interval / cache TTL")
	minCPU := flag.Float64("min-cpu", 0.5, "hide processes below this CPU% (unless they have ports/sockets)")
	minMB := flag.Float64("min-mb", 40, "hide processes below this RAM in MB (unless they have ports/sockets)")
	noOpen := flag.Bool("no-open", false, "do not open the browser")
	flag.Parse()

	nowUnix = func() int64 { return time.Now().Unix() }

	col := &collector{minCPU: *minCPU, minMB: *minMB}
	cache := &snapCache{col: col, ttl: *interval}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/snapshot", func(w http.ResponseWriter, r *http.Request) {
		snap, err := cache.get(r.Context())
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(snap)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		b, _ := webFS.ReadFile("web/index.html")
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(b)
	})

	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	url := fmt.Sprintf("http://%s/", ln.Addr().String())
	fmt.Printf("fleetmap → %s  (refresh %s)\n", url, interval.String())
	if !*noOpen {
		_ = exec.Command("open", url).Start()
	}
	log.Fatal(http.Serve(ln, mux))
}

// snapCache serves one shared snapshot to every browser client, recomputed at
// most once per TTL so N tabs don't thrash lsof.
type snapCache struct {
	col *collector
	ttl time.Duration

	mu   sync.Mutex
	at   time.Time
	snap Snapshot
}

func (c *snapCache) get(ctx context.Context) (Snapshot, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.at.IsZero() && time.Since(c.at) < c.ttl {
		return c.snap, nil
	}
	cctx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	snap, err := c.col.collect(cctx)
	if err != nil {
		if !c.at.IsZero() {
			return c.snap, nil // serve stale rather than fail
		}
		return Snapshot{}, err
	}
	c.snap = snap
	c.at = time.Now()
	return snap, nil
}
