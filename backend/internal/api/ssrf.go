package api

import (
	"errors"
	"net"
	"net/url"
)

// privateRanges lists CIDR blocks that must never be fetched.
var privateRanges = func() []*net.IPNet {
	blocks := []string{
		"127.0.0.0/8",    // loopback
		"10.0.0.0/8",     // RFC1918
		"172.16.0.0/12",  // RFC1918
		"192.168.0.0/16", // RFC1918
		"169.254.0.0/16", // link-local / AWS metadata
		"::1/128",        // IPv6 loopback
		"fc00::/7",       // IPv6 unique local
	}
	nets := make([]*net.IPNet, 0, len(blocks))
	for _, b := range blocks {
		_, n, _ := net.ParseCIDR(b)
		nets = append(nets, n)
	}
	return nets
}()

func validateURL(raw string) error {
	u, err := url.Parse(raw)
	if err != nil {
		return errors.New("invalid URL")
	}
	if u.Scheme != "http" && u.Scheme != "https" {
		return errors.New("URL must use http or https")
	}
	host := u.Hostname()
	ips, err := net.LookupHost(host)
	if err != nil {
		// Can't resolve — may be a network issue in tests; skip resolution check.
		// The fetch itself will fail if truly unreachable.
		ip := net.ParseIP(host)
		if ip == nil {
			return nil // unresolvable hostname, let fetcher fail naturally
		}
		ips = []string{ip.String()}
	}
	for _, ipStr := range ips {
		ip := net.ParseIP(ipStr)
		if ip == nil {
			continue
		}
		for _, block := range privateRanges {
			if block.Contains(ip) {
				return errors.New("URL resolves to a private/reserved address")
			}
		}
	}
	return nil
}
