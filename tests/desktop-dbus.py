"""Exercise theme signals and tray callbacks across the real D-Bus filter."""

import asyncio
import os
import sys

from dbus_next import Message, MessageType, Variant
from dbus_next.aio import MessageBus
from dbus_next.service import ServiceInterface, method, signal


class Settings(ServiceInterface):
    def __init__(self):
        super().__init__("org.freedesktop.portal.Settings")
        self.scheme = 1

    @method()
    def ReadOne(self, namespace: "s", key: "s") -> "v":
        return Variant("u", self.scheme)

    @method()
    def Read(self, namespace: "s", key: "s") -> "v":
        return Variant("v", Variant("u", self.scheme))

    @method()
    def ReadAll(self, namespaces: "as") -> "a{sa{sv}}":
        return {"org.freedesktop.appearance": {"color-scheme": Variant("u", self.scheme)}}

    @signal()
    def SettingChanged(self) -> "ssv":
        return ["org.freedesktop.appearance", "color-scheme", Variant("u", self.scheme)]


class Tray(ServiceInterface):
    def __init__(self):
        super().__init__("org.kde.StatusNotifierItem")
        self.activated = asyncio.Event()

    @method()
    def Activate(self, x: "i", y: "i"):
        self.activated.set()


class OpenURI(ServiceInterface):
    def __init__(self):
        super().__init__("org.freedesktop.portal.OpenURI")

    @method()
    def OpenURI(self, parent: "s", uri: "s", options: "a{sv}"):
        pass


class FileChooser(ServiceInterface):
    def __init__(self):
        super().__init__("org.freedesktop.portal.FileChooser")

    @method()
    def OpenFile(self, parent: "s", title: "s", options: "a{sv}"):
        pass


async def checked_call(bus, **args):
    reply = await bus.call(Message(**args))
    assert reply.message_type == MessageType.METHOD_RETURN, reply.body
    return reply.body


async def host():
    portal = await MessageBus().connect()
    settings = Settings()
    portal.export("/org/freedesktop/portal/desktop", settings)
    portal.export("/org/freedesktop/portal/desktop", OpenURI())
    portal.export("/org/freedesktop/portal/desktop", FileChooser())
    await portal.request_name("org.freedesktop.portal.Desktop")

    # A different owner prevents the tray's TALK rule from bypassing portal filters.
    watcher = await MessageBus().connect()
    await watcher.request_name("org.kde.StatusNotifierWatcher")

    async def activate(name):
        await checked_call(watcher, destination=name, path="/StatusNotifierItem",
                           interface="org.kde.StatusNotifierItem", member="Activate",
                           signature="ii", body=[0, 0])

    def handle(msg):
        if msg.message_type == MessageType.METHOD_CALL and msg.member == "RegisterStatusNotifierItem":
            asyncio.create_task(activate(msg.body[0]))
            return Message.new_method_return(msg)

    watcher.add_message_handler(handle)
    print("READY", flush=True)
    while True:
        await asyncio.sleep(0.2)
        settings.scheme = 3 - settings.scheme
        settings.SettingChanged()


async def client(tray):
    bus = await MessageBus().connect()
    changed = asyncio.Event()

    def handle(msg):
        if msg.interface == "org.freedesktop.portal.Settings" and msg.member == "SettingChanged":
            assert msg.body[:2] == ["org.freedesktop.appearance", "color-scheme"]
            assert msg.body[2].value in (1, 2)
            changed.set()

    bus.add_message_handler(handle)
    await checked_call(bus, destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                       interface="org.freedesktop.DBus", member="AddMatch", signature="s",
                       body=["type='signal',sender='org.freedesktop.portal.Desktop',interface='org.freedesktop.portal.Settings',member='SettingChanged'"])
    for member, signature, body in [
        ("ReadOne", "ss", ["org.freedesktop.appearance", "color-scheme"]),
        ("Read", "ss", ["org.freedesktop.appearance", "color-scheme"]),
        ("ReadAll", "as", [["org.freedesktop.appearance"]]),
    ]:
        result = await checked_call(bus, destination="org.freedesktop.portal.Desktop",
                                    path="/org/freedesktop/portal/desktop",
                                    interface="org.freedesktop.portal.Settings", member=member,
                                    signature=signature, body=body)
        value = result[0]
        if member == "ReadAll":
            value = value["org.freedesktop.appearance"]["color-scheme"].value
        else:
            while isinstance(value, Variant):
                value = value.value
        assert value in (1, 2)
    await asyncio.wait_for(changed.wait(), 5)
    if tray:
        item = Tray()
        bus.export("/StatusNotifierItem", item)
        name = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
        assert (await bus.request_name(name)).name == "PRIMARY_OWNER"
        await checked_call(bus, destination="org.kde.StatusNotifierWatcher", path="/StatusNotifierWatcher",
                           interface="org.kde.StatusNotifierWatcher", member="RegisterStatusNotifierItem",
                           signature="s", body=[name])
        await asyncio.wait_for(item.activated.wait(), 5)
        # Drain the reply to Activate before closing the connection.
        await checked_call(bus, destination="org.freedesktop.DBus", path="/org/freedesktop/DBus",
                           interface="org.freedesktop.DBus", member="GetId")
    bus.disconnect()
    await bus.wait_for_disconnect()


asyncio.run(host() if sys.argv[1] == "host" else client(sys.argv[1] == "tray"))
