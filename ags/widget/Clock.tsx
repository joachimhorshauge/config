import { Gtk } from "ags/gtk4";
import { createPoll as poll } from "ags/time";
import { createState, createComputed } from "ags";
import GLib from "gi://GLib?version=2.0";

export default function Clock() {
    const [showSeconds, setShowSeconds] = createState(false)
    const [hovered, setHovered] = createState(false)

    const time = poll("", showSeconds() ? 1000 : 60000, () => {
        return GLib.DateTime.new_now_local()?.format(showSeconds() ? "%H:%M:%S" : "%H:%M") ?? "";
    });

    const date = poll("", 60000, () => {
        return GLib.DateTime.new_now_local()?.format("%A, %B %e") ?? "";
    });

    function toggleSeconds() {
        setShowSeconds(prev => !prev);
    }


    return (
        <button class="clock" onClicked={toggleSeconds}>
            <Gtk.EventControllerMotion
                onEnter={() => setHovered(true)}
                onLeave={() => setHovered(false)}
            />
            <box orientation={Gtk.Orientation.VERTICAL}>
                <box class="clock-time-row" halign={Gtk.Align.END}>
                    <label class="clock-time" label={time} halign={Gtk.Align.END}></label>
                    <image iconName="preferences-system-time-symbolic" pixelSize={18}></image>
                </box>
                <revealer transitionType={Gtk.RevealerTransitionType.SLIDE_DOWN} revealChild={hovered}>
                    <label class="clock-date" label={date}></label>
                </revealer>
            </box>
        </button>
    )
}