// Regression tests for recursive group loading. Compile with monkeyc -t and run
// with monkeydo <program> <device> /t. Test code is omitted from normal builds.
using Toybox.Lang;
using Toybox.Test;
using Toybox.WatchUi;

(:test)
module GroupLoadingTests {
    function info(name as Lang.String) as Lang.Dictionary {
        return { "type" => "info", "name" => name, "content" => name };
    }

    function group(name as Lang.String, lazy as Lang.Boolean, delayed as Lang.Boolean, items as Lang.Array) as Lang.Dictionary {
        return {
            "type" => "group", "name" => name, "title" => name,
            "content" => name, "lazy_loading" => lazy,
            "delayed_load" => delayed, "items" => items
        };
    }

    function view(items as Lang.Array) as HomeAssistantView {
        return new HomeAssistantView({ "title" => "Test", "items" => items }, null);
    }

    function labels(menu as HomeAssistantView, delayed as Lang.Boolean) as Lang.String {
        var result = "";
        var items = menu.getItemsToUpdate(delayed, false);
        for (var i = 0; i < items.size(); i++) {
            result += items[i].getLabel() + ",";
        }
        return result;
    }

    function childGroup(menu as HomeAssistantView, index as Lang.Number) as HomeAssistantGroupMenuItem {
        return HomeAssistantMenuItem.getDisplayedItem(menu.getItem(index)) as HomeAssistantGroupMenuItem;
    }

    (:test)
    function defaultsRemainEager(logger as Test.Logger) as Lang.Boolean {
        var menu = view([info("first"), {
            "type" => "group", "name" => "default", "items" => [info("child")]
        }, group("false", false, false, [info("grandchild")])]);
        Test.assertEqual(labels(menu, false), "first,child,false,grandchild,");
        Test.assertEqual(labels(menu, true), "");
        return true;
    }

    (:test)
    function lazyOpenCloseReopen(logger as Test.Logger) as Lang.Boolean {
        var menu = view([info("first"), group("forecast", true, false, [
            info("today"), group("daily", false, false, [info("tomorrow")])
        ])]);
        Test.assertEqual(labels(menu, false), "first,forecast,");
        var forecast = childGroup(menu, 1);
        forecast.setEntered(true);
        Test.assertEqual(labels(menu, false), "first,forecast,today,daily,tomorrow,");
        forecast.setEntered(false);
        Test.assertEqual(labels(menu, false), "first,forecast,");
        forecast.setEntered(true);
        Test.assertEqual(labels(menu, false), "first,forecast,today,daily,tomorrow,");
        return true;
    }

    (:test)
    function nestedLazyGroupsWaitForEntry(logger as Test.Logger) as Lang.Boolean {
        var menu = view([group("outer", true, false, [
            group("inner", true, false, [info("value")])
        ])]);
        var outer = childGroup(menu, 0);
        outer.setEntered(true);
        Test.assertEqual(labels(menu, false), "outer,inner,");
        var inner = childGroup(outer.getMenuView(), 0);
        inner.setEntered(true);
        Test.assertEqual(labels(menu, false), "outer,inner,value,");
        inner.setEntered(false);
        Test.assertEqual(labels(menu, false), "outer,inner,");
        outer.setEntered(false);
        Test.assertEqual(labels(menu, false), "outer,");
        return true;
    }

    (:test)
    function delayedDescendantsAndInheritedDelay(logger as Test.Logger) as Lang.Boolean {
        var menu = view([info("first"), group("forecast", false, true, [
            info("today"), group("daily", false, false, [info("tomorrow")])
        ]), info("last")]);
        Test.assertEqual(labels(menu, false), "first,forecast,last,");
        Test.assertEqual(labels(menu, true), "today,daily,tomorrow,");
        Test.assertEqual(labels(menu, false), "first,forecast,last,");
        return true;
    }

    (:test)
    function lazyAndDelayedCombine(logger as Test.Logger) as Lang.Boolean {
        var menu = view([group("forecast", true, true, [info("today")])]);
        Test.assertEqual(labels(menu, false), "forecast,");
        Test.assertEqual(labels(menu, true), "");
        var forecast = childGroup(menu, 0);
        forecast.setEntered(true);
        Test.assertEqual(labels(menu, false), "forecast,");
        Test.assertEqual(labels(menu, true), "today,");
        forecast.setEntered(false);
        Test.assertEqual(labels(menu, true), "");
        return true;
    }

    (:test)
    function disabledAndEmptyGroups(logger as Test.Logger) as Lang.Boolean {
        var disabled = group("disabled", false, false, [info("hidden")]);
        disabled["enabled"] = false;
        var empty = group("empty", true, true, []);
        empty.remove("content");
        var menu = view([disabled, empty]);
        Test.assertEqual(labels(menu, false), "");
        Test.assertEqual(labels(menu, true), "");
        childGroup(menu, 0).setEntered(true);
        Test.assertEqual(labels(menu, true), "");
        return true;
    }

    (:test)
    function stateItemsFollowTheirGroupBatch(logger as Test.Logger) as Lang.Boolean {
        var menu = view([group("controls", true, true, [
            { "type" => "toggle", "name" => "toggle", "entity" => "light.test" },
            { "type" => "numeric", "name" => "numeric", "entity" => "light.test",
              "tap_action" => { "action" => "light.turn_on", "picker" => { "min" => 0, "max" => 100, "step" => 1, "data_attribute" => "brightness_pct" } } },
            { "type" => "select", "name" => "select", "entity" => "select.test" }
        ])]);
        Test.assertEqual(labels(menu, true), "");
        childGroup(menu, 0).setEntered(true);
        Test.assertEqual(labels(menu, false), "controls,");
        Test.assertEqual(labels(menu, true), ($ has :HomeAssistantSelectMenuItem) ? "toggle,numeric,select," : "toggle,numeric,");
        return true;
    }

    (:test)
    function plainMenuItemsKeepLoadingPolicy(logger as Test.Logger) as Lang.Boolean {
        Toybox.Application.Properties.setValue("show_type_icons", false);
        Settings.update();
        var menu = view([group("forecast", true, false, [info("today")])]);
        Test.assertEqual(labels(menu, false), "forecast,");
        var forecast = childGroup(menu, 0);
        forecast.setEntered(true);
        Test.assertEqual(labels(menu, false), "forecast,today,");
        forecast.setEntered(false);
        Test.assertEqual(labels(menu, false), "forecast,");
        Toybox.Application.Properties.setValue("show_type_icons", true);
        Settings.update();
        return true;
    }
}
