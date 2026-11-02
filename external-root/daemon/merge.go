package main

import (
	"net"
	"sync"
)

type mergedListener struct {
	listeners []net.Listener
	ready     chan net.Conn
	errors    chan error
	done      chan struct{}
	once      sync.Once
}

func mergeListeners(listeners ...net.Listener) net.Listener {
	merged := &mergedListener{listeners: listeners, ready: make(chan net.Conn, 32), errors: make(chan error, len(listeners)), done: make(chan struct{})}
	for _, listener := range listeners {
		go func(listener net.Listener) {
			for {
				connection, err := listener.Accept()
				if err != nil {
					select {
					case merged.errors <- err:
					case <-merged.done:
					}
					return
				}
				select {
				case merged.ready <- connection:
				case <-merged.done:
					_ = connection.Close()
					return
				}
			}
		}(listener)
	}
	return merged
}
func (l *mergedListener) Accept() (net.Conn, error) {
	select {
	case connection := <-l.ready:
		return connection, nil
	case err := <-l.errors:
		return nil, err
	case <-l.done:
		return nil, net.ErrClosed
	}
}
func (l *mergedListener) Addr() net.Addr { return l.listeners[0].Addr() }
func (l *mergedListener) Close() error {
	l.once.Do(func() {
		close(l.done)
		for _, listener := range l.listeners {
			_ = listener.Close()
		}
	})
	return nil
}
