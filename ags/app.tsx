import app from "ags/gtk4/app"
import { Astal } from "ags/gtk4"
import style from "./styles/style.css"
import Clock from "./widget/Clock";

function Workspaces() {
    const workspaces = [1, 2, 3, 4, 5];

    return (
        <box>
            {workspaces.map((ws) => (
                <button>
                    <label label={ws.toString()}></label>
                </button>
            ))}
        </box>
    );

}



app.start({
    css: style,
    main() {
        const { TOP, RIGHT} = Astal.WindowAnchor;
        return (
            <window visible anchor={ TOP | RIGHT }>
                <Clock/>
            </window>
        );
    }
})

