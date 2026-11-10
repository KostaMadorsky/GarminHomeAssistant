// Distributed under MIT Licence.
// Request-level regression tests. No HTTP calls or polling timers are started.
using Toybox.Application.Properties;
using Toybox.Application.Storage;
using Toybox.Communications;
using Toybox.Lang;
using Toybox.Test;
using Toybox.WatchUi;

(:test)
class MenuUpdateRecordingApp extends HomeAssistantApp {
    var requests as Lang.Array<Lang.Dictionary> = [];
    var delays as Lang.Array<Lang.Number> = [];
    var cacheChecks as Lang.Number = 0;

    function initialize() {
        HomeAssistantApp.initialize();
    }

    function requestMenuUpdate(templates as Lang.Dictionary) as Void {
        requests.add(templates);
    }

    function scheduleMenuUpdate(delay as Lang.Number) as Void {
        delays.add(delay);
    }

    function fetchMenuConfigBasic(responseCallback) {
        cacheChecks += 1;
    }

    function publishApiStatus(s as Lang.String) as Void {}
}

(:test)
class MenuUpdateFixture {
    private var mSaved as Lang.Dictionary = {};
    var app as MenuUpdateRecordingApp;
    var menu as HomeAssistantView;

    function initialize(items as Lang.Array, cacheCheck as Lang.Boolean, pollDelay as Lang.Number) {
        var values = {
            "api_key" => "", "webhook_id" => "", "app_timeout" => 0,
            "poll_delay_combined" => pollDelay, "enable_menu_update_check" => cacheCheck,
            "cache_config" => cacheCheck, "show_type_icons" => true,
            "clear_webhook_id" => false
        };
        var keys = values.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i] as Lang.String;
            mSaved[key] = Properties.getValue(key);
            Properties.setValue(key, values[key]);
        }
        Settings.update();
        app = new MenuUpdateRecordingApp();
        // An empty API key returns before any startup HTTP or registration calls,
        // after the production quit/update timers have been constructed.
        app.getInitialView();
        menu = app.buildMenu({ "title" => "Test", "items" => items });
    }

    function restore() as Void {
        app.getQuitTimer().stop();
        var keys = mSaved.keys();
        for (var i = 0; i < keys.size(); i++) {
            var key = keys[i] as Lang.String;
            Properties.setValue(key, mSaved[key]);
        }
        Settings.update();
    }
}

(:test)
module MenuUpdateTests {
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

    function childGroup(menu as HomeAssistantView, index as Lang.Number) as HomeAssistantGroupMenuItem {
        return HomeAssistantMenuItem.getDisplayedItem(menu.getItem(index)) as HomeAssistantGroupMenuItem;
    }

    function template(request as Lang.Dictionary, key as Lang.String) as Lang.String {
        return (request[key] as Lang.Dictionary)["template"] as Lang.String;
    }

    function enter(app as MenuUpdateRecordingApp, item as HomeAssistantGroupMenuItem, value as Lang.Boolean) as Void {
        // Match the production delegate: ordinary group navigation preserves the
        // cached batch and an outstanding response.
        if (item.setEntered(value)) {
            app.menuNavigationChanged();
        }
    }

    (:test)
    function ordinaryBeforeDelayedAndReuseBothBatches(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("forecast", false, true, [info("today")])
        ], false, 1);
        try {
            var app = fixture.app;
            app.startUpdates();
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.requests[0].size(), 2);
            Test.assertEqual(template(app.requests[0], "0"), "ordinary");
            Test.assertEqual(template(app.requests[0], "1"), "forecast");
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 1);
            app.onReturnUpdateMenuItems(200, { "0" => "ready", "1" => "summary" });
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.requests[1].size(), 1);
            Test.assertEqual(template(app.requests[1], "0"), "today");
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            app.onReturnUpdateMenuItems(200, { "0" => "sunny" });
            Test.assertEqual(app.delays[0], 1000);
            app.updateMenuItems();
            Test.assert(app.requests[0] == app.requests[2]);
            app.onReturnUpdateMenuItems(200, {});
            Test.assert(app.requests[1] == app.requests[3]);
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function eagerNavigationPreservesRequestAndCache(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("controls", false, false, [info("value")])
        ], false, 1);
        try {
            var app = fixture.app;
            var controls = childGroup(fixture.menu, 1);
            app.startUpdates();
            enter(app, controls, true);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 1);
            app.onReturnUpdateMenuItems(200, { "0" => "root", "1" => "group", "2" => "child" });
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "root");
            Test.assertEqual(controls.getMenuView().getItem(0).getSubLabel(), "child");
            Test.assertEqual(app.requests.size(), 1);
            enter(app, controls, false);
            Test.assertEqual(app.requests.size(), 1);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            Test.assert(app.requests[0] == app.requests[1]);
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function lazyNavigationKeepsIndexesAndSuppressesStaleResponses(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("forecast", true, false, [info("today")])
        ], false, 1);
        try {
            var app = fixture.app;
            var forecast = childGroup(fixture.menu, 1);
            app.startUpdates();
            Test.assertEqual(app.requests[0].size(), 2);
            enter(app, forecast, true);
            Test.assertEqual(app.requests.size(), 1);
            app.onReturnUpdateMenuItems(200, { "0" => "stale-root", "1" => "stale-summary" });
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.requests[1].size(), 3);
            Test.assert(fixture.menu.getItem(0).getSubLabel() == null);
            Test.assertEqual(template(app.requests[1], "2"), "today");
            app.onReturnUpdateMenuItems(200, { "0" => "root", "1" => "summary", "2" => "sunny" });
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "root");
            Test.assertEqual(forecast.getMenuView().getItem(0).getSubLabel(), "sunny");
            enter(app, forecast, false);
            Test.assertEqual(app.requests.size(), 3);
            Test.assertEqual(app.requests[2].size(), 2);
            app.onReturnUpdateMenuItems(200, {});
            // Reopening while a new request is pending, then closing again,
            // must not apply a response to any now-excluded descendants.
            enter(app, forecast, true);
            Test.assertEqual(app.requests[3].size(), 3);
            enter(app, forecast, false);
            app.onReturnUpdateMenuItems(200, { "0" => "stale-root", "1" => "stale-summary", "2" => "stale-child" });
            Test.assertEqual(app.requests.size(), 5);
            Test.assertEqual(app.requests[4].size(), 2);
            Test.assertEqual(forecast.getMenuView().getItem(0).getSubLabel(), "sunny");
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function nestedLazyEligibilityIsRespectedByRequests(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            group("outer", true, false, [group("inner", true, true, [info("value")])])
        ], false, 1);
        try {
            var app = fixture.app;
            var outer = childGroup(fixture.menu, 0);
            app.startUpdates();
            Test.assertEqual(app.requests[0].size(), 1);
            app.onReturnUpdateMenuItems(200, {});
            enter(app, outer, true);
            Test.assertEqual(app.requests[1].size(), 2);
            app.onReturnUpdateMenuItems(200, {});
            var inner = childGroup(outer.getMenuView(), 0);
            enter(app, inner, true);
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(template(app.requests[3], "0"), "value");
            app.onReturnUpdateMenuItems(200, {});
            enter(app, inner, false);
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(app.requests.size(), 5);
            enter(app, outer, false);
            Test.assertEqual(app.requests[5].size(), 1);
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function delayedFailuresResumeOrdinaryBeforeRetry(logger as Test.Logger) as Lang.Boolean {
        var failures = [Communications.NETWORK_RESPONSE_OUT_OF_MEMORY, 400, 200];
        for (var i = 0; i < failures.size(); i++) {
            var fixture = new MenuUpdateFixture([
                info("ordinary"), group("forecast", false, true, [info("today")])
            ], false, 1);
            try {
                var app = fixture.app;
                app.startUpdates();
                app.onReturnUpdateMenuItems(200, {});
                Test.assertEqual(template(app.requests[1], "0"), "today");
                app.onReturnUpdateMenuItems(failures[i], null);
                // No immediate retry or active timer: scheduling is recorded.
                Test.assertEqual(app.requests.size(), 2);
                Test.assertEqual(app.delays.size(), 1);
                if (failures[i] == Communications.NETWORK_RESPONSE_OUT_OF_MEMORY) {
                    Test.assertEqual(app.delays[0], Globals.scApiBackoffMs);
                }
                app.updateMenuItems();
                Test.assertEqual(template(app.requests[2], "0"), "ordinary");
                app.onReturnUpdateMenuItems(200, {});
                Test.assertEqual(template(app.requests[3], "0"), "today");
                app.onReturnUpdateMenuItems(200, {});
            } finally {
                fixture.restore();
            }
        }
        return true;
    }

    (:test)
    function emptyMenusUseTimerInsteadOfRecursion(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([], false, 0);
        try {
            fixture.app.startUpdates();
            Test.assertEqual(fixture.app.requests.size(), 0);
            Test.assertEqual(fixture.app.delays.size(), 1);
            Test.assertEqual(fixture.app.delays[0], 1000);
            fixture.app.updateMenuItems();
            Test.assertEqual(fixture.app.requests.size(), 0);
            Test.assertEqual(fixture.app.delays.size(), 2);
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function delayedOnlyMenuSkipsEmptyOrdinaryRequest(logger as Test.Logger) as Lang.Boolean {
        var delayed = group("forecast", false, true, [info("today")]);
        delayed.remove("content");
        var fixture = new MenuUpdateFixture([delayed], false, 1);
        try {
            var app = fixture.app;
            app.startUpdates();
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.requests[0].size(), 1);
            Test.assertEqual(template(app.requests[0], "0"), "today");
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(app.delays[0], 1000);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            Test.assert(app.requests[0] == app.requests[1]);
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function cacheCheckBlocksNavigationAndDuplicateRequests(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("forecast", true, false, [info("today")])
        ], true, 1);
        try {
            var app = fixture.app;
            var forecast = childGroup(fixture.menu, 1);
            app.startUpdates();
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(app.cacheChecks, 1);
            enter(app, forecast, true);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.cacheChecks, 1);
            // OOM avoids reading/writing stored menu data while exercising the
            // production cache callback's unlock and retry scheduling.
            app.onReturnCheckMenuConfig(Communications.NETWORK_RESPONSE_OUT_OF_MEMORY, null);
            Test.assertEqual(app.delays.size(), 1);
            Test.assertEqual(app.delays[0], Globals.scApiBackoffMs);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.requests[1].size(), 3);
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(app.cacheChecks, 1);
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function actionRefreshWaitsForRenderAndReusesOrdinaryBatch(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("forecast", false, true, [info("today")])
        ], false, 1);
        try {
            var app = fixture.app;
            app.startUpdates();
            app.forceStatusUpdates();
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 1);
            app.onReturnUpdateMenuItems(200, { "0" => "before-action", "1" => "before-action" });
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.delays.size(), 0);
            Test.assert(app.requests[0] == app.requests[1]);
            Test.assert(fixture.menu.getItem(0).getSubLabel() == null);
            app.onReturnUpdateMenuItems(200, { "0" => "after-action", "1" => "summary" });
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "after-action");
            Test.assertEqual(template(app.requests[2], "0"), "today");
            app.onReturnUpdateMenuItems(200, {});
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function actionRefreshWaitsForCacheCheckWithoutPollDelay(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([info("ordinary")], true, 1);
        var previousMenu = Storage.getValue(HomeAssistantApp.scStorageKeyMenu);
        var cachedMenu = { "title" => "Synthetic", "items" => [] };
        try {
            // Compare against identical synthetic storage so the successful cache
            // callback does not publish a new menu or require real config data.
            Storage.setValue(HomeAssistantApp.scStorageKeyMenu, cachedMenu);
            var app = fixture.app;
            app.startUpdates();
            app.onReturnUpdateMenuItems(200, { "0" => "before-action" });
            Test.assertEqual(app.cacheChecks, 1);
            app.forceStatusUpdates();
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.cacheChecks, 1);
            app.onReturnCheckMenuConfig(200, cachedMenu);
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.delays.size(), 0);
            Test.assert(app.requests[0] == app.requests[1]);
            app.onReturnUpdateMenuItems(200, { "0" => "after-action" });
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "after-action");
            Test.assertEqual(app.cacheChecks, 1);
        } finally {
            if (previousMenu == null) {
                Storage.deleteValue(HomeAssistantApp.scStorageKeyMenu);
            } else {
                Storage.setValue(HomeAssistantApp.scStorageKeyMenu, previousMenu);
            }
            fixture.restore();
        }
        return true;
    }

    (:test)
    function cacheMemoryRetryDoesNotDiscardFreshActionResponse(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([info("ordinary")], true, 1);
        try {
            var app = fixture.app;
            app.startUpdates();
            app.onReturnUpdateMenuItems(200, { "0" => "before-action" });
            Test.assertEqual(app.cacheChecks, 1);
            app.forceStatusUpdates();
            app.onReturnCheckMenuConfig(Communications.NETWORK_RESPONSE_OUT_OF_MEMORY, null);
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.delays[0], Globals.scApiBackoffMs);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            Test.assert(app.requests[0] == app.requests[1]);
            app.onReturnUpdateMenuItems(200, { "0" => "after-action" });
            // The pending action belongs to the failed cache request. The new
            // response is current and must be applied instead of re-requested.
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "after-action");
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.cacheChecks, 1);
            Test.assertEqual(app.delays.size(), 2);
        } finally {
            fixture.restore();
        }
        return true;
    }

    (:test)
    function staleMemoryResponseStillBacksOff(logger as Test.Logger) as Lang.Boolean {
        // Both lazy navigation and an action can invalidate an in-flight result.
        for (var i = 0; i < 2; i++) {
            var fixture = new MenuUpdateFixture([
                info("ordinary"), group("forecast", true, false, [info("today")])
            ], false, 1);
            try {
                var app = fixture.app;
                app.startUpdates();
                if (i == 0) {
                    enter(app, childGroup(fixture.menu, 1), true);
                } else {
                    app.forceStatusUpdates();
                }
                app.onReturnUpdateMenuItems(Communications.NETWORK_RESPONSE_OUT_OF_MEMORY, null);
                Test.assertEqual(app.requests.size(), 1);
                Test.assertEqual(app.delays.size(), 1);
                Test.assertEqual(app.delays[0], Globals.scApiBackoffMs);
                app.updateMenuItems();
                Test.assertEqual(app.requests.size(), 2);
                Test.assertEqual(app.requests[1].size(), i == 0 ? 3 : 2);
                if (i == 1) {
                    Test.assert(app.requests[0] == app.requests[1]);
                }
                app.onReturnUpdateMenuItems(200, { "0" => "current", "1" => "summary", "2" => "sunny" });
                Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "current");
                Test.assertEqual(app.requests.size(), 2);
            } finally {
                fixture.restore();
            }
        }
        return true;
    }

    (:test)
    function nullCacheSuccessResumesPollingAfterBackoff(logger as Test.Logger) as Lang.Boolean {
        var fixture = new MenuUpdateFixture([
            info("ordinary"), group("forecast", true, false, [info("today")])
        ], true, 1);
        try {
            var app = fixture.app;
            app.startUpdates();
            app.onReturnUpdateMenuItems(200, {});
            Test.assertEqual(app.cacheChecks, 1);
            enter(app, childGroup(fixture.menu, 1), true);
            app.onReturnCheckMenuConfig(200, null);
            Test.assertEqual(app.requests.size(), 1);
            Test.assertEqual(app.delays.size(), 1);
            Test.assertEqual(app.delays[0], Globals.scApiBackoffMs);
            app.updateMenuItems();
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.requests[1].size(), 3);
            app.onReturnUpdateMenuItems(200, { "0" => "current", "1" => "summary", "2" => "sunny" });
            Test.assertEqual(fixture.menu.getItem(0).getSubLabel(), "current");
            Test.assertEqual(app.requests.size(), 2);
            Test.assertEqual(app.cacheChecks, 2);
        } finally {
            fixture.restore();
        }
        return true;
    }
}
