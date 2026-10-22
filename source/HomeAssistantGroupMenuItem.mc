//-----------------------------------------------------------------------------------
//
// Distributed under MIT Licence
//   See https://github.com/house-of-abbey/GarminHomeAssistant/blob/main/LICENSE
//
//-----------------------------------------------------------------------------------
//
// GarminHomeAssistant is a Garmin IQ application written in Monkey C and routinely
// tested on a Venu 2 device. The source code is provided at:
//            https://github.com/house-of-abbey/GarminHomeAssistant
//
// P A Abbey & J D Abbey & Someone0nEarth, 31 October 2023
//
//-----------------------------------------------------------------------------------

using Toybox.Lang;
using Toybox.WatchUi;

//! Menu button with an icon that opens a sub-menu, i.e. group, and optionally renders
//! a Home Assistant Template.
//
class HomeAssistantGroupMenuItem extends HomeAssistantMenuItem {
    private var mMenu as HomeAssistantView?;
    private var mDefinition as Lang.Dictionary?;
    private var mLazyLoading as Lang.Boolean;
    private var mDelayedLoad as Lang.Boolean;
    private var mEntered as Lang.Boolean = false;

    //! Class Constructor
    //
    function initialize(
        definition as Lang.Dictionary,
        template   as Lang.String,
        icon       as WatchUi.Drawable,
        options    as {
            :alignment as WatchUi.MenuItem.Alignment
        }?
    ) {
        if (options != null) {
            options[:icon] = icon;
        } else {
            options = { :icon => icon };
        }

        HomeAssistantMenuItem.initialize(
            definition.get("name") as Lang.String,
            template,
            options
        );

        mLazyLoading = definition.get("lazy_loading") == true;
        mDelayedLoad = definition.get("delayed_load") == true;
        if (mLazyLoading || mDelayedLoad) {
            mDefinition = definition;
        } else {
            mMenu = new HomeAssistantView(definition, null);
        }
    }

    //! Return the submenu for this group menu item.
    //
    function getMenuView() as HomeAssistantView {
        if (mMenu == null) {
            mMenu = new HomeAssistantView(mDefinition, null);
            mDefinition = null;
        }
        return mMenu;
    }

    //! Lazy descendants refresh only while this group is on the navigation path.
    function setEntered(entered as Lang.Boolean) as Void {
        mEntered = entered;
    }

    function shouldUpdateChildren() as Lang.Boolean {
        return !mLazyLoading || mEntered;
    }

    function isDelayedLoad() as Lang.Boolean {
        return mDelayedLoad;
    }

}
