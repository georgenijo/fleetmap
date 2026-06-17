package main

import (
	"regexp"
	"strings"
)

// redact masks anything in a command line that looks like a credential, so the
// fleet map can render full cmdlines in a browser without leaking secrets.
// localhost-only binding is the first line of defense; this is the second.

var (
	// key=value / --key value where the key name smells like a secret.
	kvSecret = regexp.MustCompile(`(?i)\b(token|secret|password|passwd|pwd|api[_-]?key|apikey|access[_-]?key|client[_-]?secret|auth|bearer|key)([=: ]+)(\S+)`)
	// standalone token shapes that are secrets regardless of the flag name.
	tokenLike = regexp.MustCompile(`\b(sk-[A-Za-z0-9_-]{12,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{12,}|ASIA[0-9A-Z]{12,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{6,})`)
	// long opaque hex/base64-ish runs (>=32) that are almost never anything but keys.
	longOpaque = regexp.MustCompile(`\b[A-Fa-f0-9]{32,}\b|\b[A-Za-z0-9+/]{40,}={0,2}\b`)
)

const mask = "•••"

func redact(cmd string) string {
	if cmd == "" {
		return cmd
	}
	cmd = kvSecret.ReplaceAllStringFunc(cmd, func(m string) string {
		g := kvSecret.FindStringSubmatch(m)
		// g[1]=key g[2]=sep g[3]=value
		return g[1] + g[2] + mask
	})
	cmd = tokenLike.ReplaceAllString(cmd, mask)
	cmd = longOpaque.ReplaceAllStringFunc(cmd, func(m string) string {
		// keep short-ish path-like segments; only mask if it really is one opaque run
		if strings.ContainsAny(m, "/\\.") {
			return m
		}
		return mask
	})
	return cmd
}
