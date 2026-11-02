import struct
from proxy_offline.framing import FrameAdapter

def frame(body):return b'SP'+struct.pack('<I',len(body))+body

def test_fragmented_and_coalesced_frames_rewrite_lengths():
    adapter=FrameAdapter(lambda body:(body+b'!',True))
    data=frame(b'one')+frame(b'two')
    output=b''.join(adapter.feed(data[i:i+1]) for i in range(len(data)))+adapter.finish()
    assert output==frame(b'one!')+frame(b'two!')

def test_unknown_protocol_and_oversize_are_losslessly_bypassed():
    for data in (b'HTTP/1.1 unknown',b'SP'+struct.pack('<I',2**31)+b'payload'):
        adapter=FrameAdapter(lambda body:(_ for _ in ()).throw(AssertionError('must not decode')))
        assert adapter.feed(data)+adapter.feed(b'more')+adapter.finish()==data+b'more'

def test_incomplete_frame_at_eof_is_not_discarded():
    adapter=FrameAdapter(lambda body:(b'changed',True))
    partial=frame(b'hello')[:-1]
    assert adapter.feed(partial)+adapter.finish()==partial

def test_transform_failure_preserves_frame():
    def failure(body):raise ValueError('bad protobuf')
    adapter=FrameAdapter(failure)
    assert adapter.feed(frame(b'bad'))==frame(b'bad')
