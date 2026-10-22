# Group loading

Large groups, such as forecasts, can add many templates to every refresh. Two optional boolean fields on a `group` control its descendants:

| Field | Default | Behaviour when `true` |
| --- | --- | --- |
| `lazy_loading` | `false` | Construct the submenu and load its descendants when opened. Refresh them only while inside that group or its submenus. Leaving the group stops their refreshes; reopening it requests fresh values. |
| `delayed_load` | `false` | Construct and render descendants in a second batch, after the ordinary batch has finished and its values have been displayed. This order applies to every refresh. |

Neither field delays or suppresses the group's own `content`: its summary belongs to its parent menu's batch. The downloaded JSON and its templates are still fetched and cached together; these fields control submenu construction and template rendering, not downloading separate menu files. A constructed submenu and its last values stay in memory when closed, but a lazy submenu is excluded from further requests until reopened.

For a forecast that refreshes only when opened:

```json
{
  "title": "Home",
  "items": [
    {
      "type": "info",
      "name": "Outdoor",
      "content": "{{ states('sensor.outdoor_temperature') }}C"
    },
    {
      "type": "group",
      "name": "Forecast",
      "title": "Forecast",
      "content": "{{ state_attr('sensor.lane_cove_forecast', 'brief') }}",
      "lazy_loading": true,
      "delayed_load": false,
      "items": [
        {
          "type": "info",
          "name": "Today",
          "content": "{{ (state_attr('sensor.lane_cove_forecast', 'daily') or ['-'])[0] }}"
        },
        {
          "type": "info",
          "name": "Tomorrow",
          "content": "{{ (state_attr('sensor.lane_cove_forecast', 'daily') or ['-', '-'])[1] }}"
        }
      ]
    }
  ]
}
```

The Outdoor value and Forecast summary refresh immediately. Today and Tomorrow are first requested when Forecast is opened. Its ordinary nested groups are included recursively; a nested group with its own `lazy_loading: true` waits until that nested group is opened. Opening a picker or entering a deeper submenu keeps its ancestor lazy groups active. Back from Forecast stops its descendants' refreshes.

For a forecast that should load automatically after the other values, set `lazy_loading` to `false` and `delayed_load` to `true`. Setting both to `true` waits for the group to be opened, then puts its descendants in the delayed batch.

Delay is inherited by all descendants. A nested `delayed_load: false` does not override an ancestor's `true`. A nested group's own summary follows the ancestor's batch, while that nested group's flags apply only to its children. Disabled groups are omitted as usual.

Requests run sequentially. Opening or leaving a group during a request waits for that request to finish, discards its response, then refreshes the current navigation path. It cannot cancel template work already running in Home Assistant. No empty render requests are sent.

Existing menus with these fields omitted or set to `false` retain their usual eager loading behaviour. Both fields are available in the JSON schema used by the menu editor; older app versions ignore them, so install an app build containing this feature before using them.
