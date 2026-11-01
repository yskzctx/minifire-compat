"""Synthetic protocol tests. No real account data or network traffic."""
from pathlib import Path

from proxy_offline.transform import ProtocolTransformer


SOURCE = Path(__file__).resolve().parents[2] / "work/apk-files/assets/AssetBundles/android/pb_32_64.ab"
protocol = ProtocolTransformer(SOURCE)


def test_terminal_login_changes_only_selected_fields():
    request = protocol.new("md.ApiLoginRequest")
    request.OpenID = "SYNTHETIC"
    request.OpenToken = "NOT-A-TOKEN"
    request.PhoneOs = 1
    request.ChannelID = 23
    request.Version = "1.0.77"
    request.VersionName = "1.0.77"
    before = request.SerializeToString()
    after, changed = protocol.terminal_login(before)
    result = protocol.parse("md.ApiLoginRequest", after)
    assert changed
    assert (result.PhoneOs, result.ChannelID) == (2, 888)
    assert (result.Version, result.VersionName) == ("1.0.79", "1.0.79")
    assert (result.OpenID, result.OpenToken) == ("SYNTHETIC", "NOT-A-TOKEN")
    assert protocol.terminal_login(after) == (after, False)
    assert after != before


def test_lobby_login_changes_only_login_body():
    login = protocol.new("md.Login")
    login.OpenID = "SYNTHETIC"
    login.Token = "NOT-A-TOKEN"
    login.Phone_Os = 1
    login.ChannelID = 23
    login.Version = "1.0.77"
    packet = protocol.new("cmdpkg.CmdPacket")
    packet.Head.Cmd = 10000
    packet.Head.Serial = 42
    packet.Body = login.SerializeToString()
    after, changed = protocol.lobby_packet(packet.SerializeToString())
    result = protocol.parse("cmdpkg.CmdPacket", after)
    body = protocol.parse("md.Login", result.Body)
    assert changed
    assert (result.Head.Cmd, result.Head.Serial) == (10000, 42)
    assert (body.Phone_Os, body.ChannelID, body.Version) == (2, 888, "1.0.79")
    assert (body.OpenID, body.Token) == ("SYNTHETIC", "NOT-A-TOKEN")


def test_other_lobby_command_is_byte_for_byte_unchanged():
    packet = protocol.new("cmdpkg.CmdPacket")
    packet.Head.Cmd = 10001
    packet.Body = b"arbitrary-body"
    data = packet.SerializeToString()
    assert protocol.lobby_packet(data) == (data, False)


def test_unknown_channel_is_byte_for_byte_unchanged():
    request = protocol.new("md.ApiLoginRequest")
    request.PhoneOs = 1
    request.ChannelID = 999
    data = request.SerializeToString()
    assert protocol.terminal_login(data) == (data, False)


def test_invalid_protobuf_is_byte_for_byte_unchanged():
    invalid = b"\xff\xff"
    assert protocol.terminal_login(invalid) == (invalid, False)
    assert protocol.lobby_packet(invalid) == (invalid, False)
