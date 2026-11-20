# config file `zerotty.json`

you can create a json config file `~/.config` dir


## Options

- `font_size`

- `fg_color`: forground or text color, can be RGB or RGBA value like "#aabbcc" or "#aabbccdd" or "skyblue".

- `bg_color`: background color, same as `fg_color` but for background.

- `window_opacity`: number from 0.0 to 1.0 to set opacity value, not the same is `bg_color` alpha value.

Note: the default value for alpha in RGB and CSS colors is FF or full. renderer uses color blending by default so `bg_color` alpha value will make a deference

<details>
<summary>All Colors</summary>

* red
* crimson
* darkred
* pink
* lightpink
* hotpink
* deeppink
* coral
* tomato
* orange
* darkorange
* gold
* yellow
* lightyellow
* lavender
* thistle
* plum
* violet
* magenta
* fuchsia
* purple
* indigo
* green
* lime
* limegreen
* forestgreen
* darkgreen
* seagreen
* olive
* aqua
* cyan
* teal
* skyblue
* dodgerblue
* blue
* navy
* darkblue
* cornsilk
* wheat
* sandybrown
* chocolate
* saddlebrown
* brown
* maroon
* white
* snow
* gainsboro
* lightgray
* silver
* gray
* dimgray
* darkgray
* black

</details>

# Example

`~/.config/zerotty.json`:

```json
{
  "font_size": 38,
  "fg_color": "white",
  "bg_color": "#0f0f0ff0",
  "window_opacity": 0.9
}
```
