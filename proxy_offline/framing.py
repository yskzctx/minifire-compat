"""Bounded SP frame adapter recovered from the local 1.0.77 frame codec.

This models the codec before sendBytes; encryption after that codec has not
been ruled out. Unknown wire data is preserved and disables rewriting.
"""
import struct


class FrameAdapter:
    def __init__(self,transform,max_body=1024*1024):
        if not 1<=max_body<=16*1024*1024:raise ValueError('invalid frame limit')
        self.transform=transform
        self.max_body=max_body
        self.buffer=bytearray()
        self.bypass=False
        self.last_event='waiting_header'

    def feed(self,data):
        if self.bypass:return bytes(data)
        self.buffer.extend(data)
        output=bytearray()
        while len(self.buffer)>=6:
            size=struct.unpack_from('<I',self.buffer,2)[0]
            if self.buffer[:2]!=b'SP' or size>self.max_body:
                self.last_event='unknown_protocol' if self.buffer[:2]!=b'SP' else 'oversize_frame'
                self.bypass=True
                output.extend(self.buffer);self.buffer.clear()
                break
            total=size+6
            if len(self.buffer)<total:
                self.last_event='waiting_body'
                break
            original=bytes(self.buffer[:total]);del self.buffer[:total]
            body=original[6:]
            try:
                rewritten,changed=self.transform(body)
                if not isinstance(rewritten,bytes) or len(rewritten)>self.max_body:
                    raise ValueError('invalid transformed frame')
                if changed:
                    output.extend(b'SP'+struct.pack('<I',len(rewritten))+rewritten)
                    self.last_event='frame_rewritten'
                else:
                    output.extend(original);self.last_event='frame_unchanged'
            except Exception:
                output.extend(original);self.last_event='transform_failed'
        return bytes(output)

    def finish(self):
        pending=bytes(self.buffer)
        self.buffer.clear()
        if pending:self.last_event='incomplete_frame_at_eof'
        return pending
