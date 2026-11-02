"""Fixed-destination loopback SP relay; no Android routing is installed."""
import socket
import socketserver
import threading
import uuid

from .framing import FrameAdapter


def make_lobby_server(address,destination,transform,journal):
    if address[0] not in ('127.0.0.1','::1'):raise ValueError('relay must bind loopback')
    if not isinstance(destination,tuple) or len(destination)!=2:raise ValueError('fixed destination required')

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            request_id=uuid.uuid4().hex
            journal.record('lobby_stream_started',request_id)
            try:remote=socket.create_connection(destination,timeout=10)
            except OSError:
                journal.record('lobby_io_failed',request_id);return
            remote.settimeout(None)
            client=self.request
            adapter=FrameAdapter(transform)

            def outbound():
                unknown=False
                try:
                    while True:
                        chunk=client.recv(65536)
                        if not chunk:break
                        previous=adapter.rewritten_count
                        result=adapter.feed(chunk)
                        if result:remote.sendall(result)
                        if adapter.rewritten_count>previous:
                            journal.record('lobby_frame_rewritten',request_id)
                        if adapter.bypass and not unknown:
                            journal.record('lobby_protocol_unknown',request_id);unknown=True
                    pending=adapter.finish()
                    if pending:remote.sendall(pending)
                except OSError:journal.record('lobby_io_failed',request_id)
                finally:
                    try:remote.shutdown(socket.SHUT_WR)
                    except OSError:pass

            thread=threading.Thread(target=outbound,daemon=True);thread.start()
            try:
                while True:
                    chunk=remote.recv(65536)
                    if not chunk:break
                    client.sendall(chunk)
            except OSError:journal.record('lobby_io_failed',request_id)
            finally:
                try:client.shutdown(socket.SHUT_RDWR)
                except OSError:pass
                remote.close();thread.join(timeout=2)
                journal.record('lobby_stream_closed',request_id)

    class Server(socketserver.ThreadingTCPServer):
        daemon_threads=True

    return Server(address,Handler)
