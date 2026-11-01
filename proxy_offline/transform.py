"""Offline protobuf rewriting for a possible process-external network adapter.

This module handles decoded message bytes only. It does not intercept TLS,
compute the game's HTTP signature, or frame its TCP stream.
"""

from google.protobuf.descriptor_pb2 import FileDescriptorSet
from google.protobuf.descriptor_pool import DescriptorPool
from google.protobuf.message_factory import GetMessageClass
from google.protobuf.message import DecodeError
import UnityPy


class ProtocolTransformer:
    def __init__(self, source):
        environment = UnityPy.load(str(source))
        files = {}
        for obj in environment.objects:
            if obj.type.name != "TextAsset":
                continue
            asset = obj.read()
            if asset.m_Name not in ("md", "Cmdpkg"):
                continue
            descriptor_set = FileDescriptorSet()
            descriptor_set.ParseFromString(asset.m_Script.encode("utf-8", "surrogateescape"))
            for file in descriptor_set.file:
                files[file.name] = file
        if not files:
            raise ValueError("protobuf descriptors absent")
        self.pool = DescriptorPool()
        pending = list(files.values())
        while pending:
            later = []
            for file in pending:
                try:
                    self.pool.AddSerializedFile(file.SerializeToString())
                except Exception:
                    later.append(file)
            if len(later) == len(pending):
                raise ValueError("protobuf descriptor dependencies unresolved")
            pending = later

    def new(self, name):
        return GetMessageClass(self.pool.FindMessageTypeByName(name))()

    def parse(self, name, data):
        message = self.new(name)
        message.ParseFromString(data)
        return message

    @staticmethod
    def _eligible(os_value, channel, version):
        return os_value in (1, 2) and channel in (23, 888) and version in (
            "1.0.77", "1.0.78", "1.0.79"
        )

    def terminal_login(self, data):
        try:
            request = self.parse("md.ApiLoginRequest", data)
        except DecodeError:
            return data, False
        if not self._eligible(request.PhoneOs, request.ChannelID, request.Version) or request.VersionName not in (
            "1.0.77", "1.0.78", "1.0.79"
        ):
            return data, False
        before = (request.PhoneOs, request.ChannelID, request.Version, request.VersionName)
        request.PhoneOs = 2
        request.ChannelID = 888
        request.Version = request.VersionName = "1.0.79"
        return (request.SerializeToString(), True) if before != (
            request.PhoneOs, request.ChannelID, request.Version, request.VersionName
        ) else (data, False)

    def lobby_packet(self, data):
        try:
            packet = self.parse("cmdpkg.CmdPacket", data)
        except DecodeError:
            return data, False
        if packet.Head.Cmd != 10000 or not packet.Body:
            return data, False
        try:
            login = self.parse("md.Login", packet.Body)
        except DecodeError:
            return data, False
        if not self._eligible(login.Phone_Os, login.ChannelID, login.Version):
            return data, False
        before = (login.Phone_Os, login.ChannelID, login.Version)
        login.Phone_Os = 2
        login.ChannelID = 888
        login.Version = "1.0.79"
        if before == (login.Phone_Os, login.ChannelID, login.Version):
            return data, False
        packet.Body = login.SerializeToString()
        return packet.SerializeToString(), True
