#!/usr/bin/env python3
"""Add the WidgetKit extension target to the Capacitor Xcode project.

`npx cap add ios` regenerates `ios/App/App.xcodeproj` from Capacitor's
template, which knows nothing about a widget. Doing this by hand in Xcode
means it is lost the next time the platform is re-added and nobody remembers
the fifteen clicks. This script is the memory, and it is idempotent: run it
as often as you like.

What it does to the project:

  App target        + WidgetBridge.swift in Sources
                    + CODE_SIGN_ENTITLEMENTS -> App/App.entitlements
                    + an "Embed Foundation Extensions" copy phase
                    + a dependency on the widget, so it always builds first
  TodoWidget target  a new app-extension target (iOS 17+, SwiftUI/WidgetKit)

Run with the venv python that has pbxproj:
    ./.tools/bin/python add-widget-target.py
"""

import os
import pathlib
import sys

try:
    from pbxproj import XcodeProject
    from pbxproj.pbxsections import (PBXBuildFile, PBXContainerItemProxy,
                                     PBXCopyFilesBuildPhase, PBXFileReference,
                                     PBXGroup, PBXNativeTarget,
                                     PBXSourcesBuildPhase, PBXTargetDependency,
                                     XCBuildConfiguration, XCConfigurationList)
except ImportError:
    sys.exit("pbxproj is missing. Run:\n"
             "  python3 -m venv .tools && ./.tools/bin/pip install pbxproj\n"
             "then re-run with ./.tools/bin/python add-widget-target.py")

HERE = pathlib.Path(__file__).resolve().parent
PROJ = HERE / "ios" / "App" / "App.xcodeproj" / "project.pbxproj"
APP_ID = "com.ahmedmohsen.todolist"
WIDGET = "TodoWidget"

if not PROJ.exists():
    sys.exit("no Xcode project at " + str(PROJ) + "\n  run: npx cap add ios --packagemanager SPM")

project = XcodeProject.load(str(PROJ))


def new(cls, **fields):
    fields["_id"] = cls._generate_id()
    fields["isa"] = cls.__name__
    obj = cls().parse(fields)
    project.objects[obj.get_id()] = obj
    return obj


def settings(config):
    """Build settings shared by the widget's Debug and Release configs."""
    s = {
        "CLANG_ENABLE_MODULES": "YES",
        "CODE_SIGN_ENTITLEMENTS": WIDGET + "/" + WIDGET + ".entitlements",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": WIDGET + "/Info.plist",
        # WidgetKit needs 14; containerBackground and the modern layout need 17.
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks",
                                    "@executable_path/../../Frameworks"],
        "MARKETING_VERSION": "1.0",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "PRODUCT_BUNDLE_IDENTIFIER": APP_ID + "." + WIDGET,
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SKIP_INSTALL": "YES",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    if config == "Debug":
        s["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        s["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
        s["DEBUG_INFORMATION_FORMAT"] = "dwarf"
    else:
        s["SWIFT_OPTIMIZATION_LEVEL"] = "-O"
        s["DEBUG_INFORMATION_FORMAT"] = "dwarf-with-dsym"
        s["COPY_PHASE_STRIP"] = "NO"
    return s


app = project.get_target_by_name("App")
if app is None:
    sys.exit("no target called App in the project")

changed = []

def group_by(name=None, path=None):
    for g in project.objects.get_objects_in_section("PBXGroup"):
        if name is not None and getattr(g, "name", None) == name:
            return g
        if path is not None and getattr(g, "path", None) == path:
            return g
    return None


def phase_of(target, isa):
    for pid in target.buildPhases:
        if project.objects[pid].isa == isa:
            return project.objects[pid]
    return None


# ── 1. the bridge plugin belongs to the app target ─────────────────────────
# Done by hand rather than with project.add_file(): that helper walks every
# existing PBXBuildFile expecting a fileRef, and Capacitor's SPM entry has a
# productRef instead, so it raises before doing anything.
# MainViewController is not optional: it is where our plugins are
# registered, and without it they are silently absent from JavaScript.
for swift in ("WidgetBridge.swift", "CalendarBridge.swift", "MainViewController.swift"):
    if project.get_files_by_name(swift):
        continue
    bridge = new(PBXFileReference, path=swift, sourceTree="<group>",
                 lastKnownFileType="sourcecode.swift")
    app_group = group_by(path="App")
    if app_group is None:
        sys.exit("cannot find the App group to put " + swift + " in")
    app_group.children.append(bridge.get_id())
    build = new(PBXBuildFile, fileRef=bridge.get_id())
    app_sources = phase_of(app, "PBXSourcesBuildPhase")
    if app_sources is None:
        sys.exit("the App target has no Sources phase")
    app_sources.files.append(build.get_id())
    changed.append(swift + " added to the App target")

# ── 2. the app signs with the App Group entitlement ────────────────────────
for cfg in project.objects.get_configurations_on_targets("App"):
    if cfg.buildSettings.get("CODE_SIGN_ENTITLEMENTS", None) != "App/App.entitlements":
        cfg.buildSettings["CODE_SIGN_ENTITLEMENTS"] = "App/App.entitlements"
        changed.append("App " + cfg.name + ": entitlements set")

# ── 2b. both targets sign with the same team ───────────────────────────────
# Set here rather than clicked in Xcode twice, so a fresh `npx cap add ios`
# does not quietly leave the widget unsigned. Override with:
#     TEAM=XXXXXXXXXX ./.tools/bin/python add-widget-target.py
# 6MCMG3FEW8 is the TEAM. The "(6DSVWXH9GY)" in the certificate name
# "Apple Development: Ahmed Hassaan (6DSVWXH9GY)" is the certificate id, NOT the
# team — using it here cost an afternoon of "No profiles were found". The team
# is the certificate's OU:
#     security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
# Z285TWPM86 is the team of the ahmedmohsen18@gmail.com Apple ID. The older
# team (6MCMG3FEW8) cannot install on the phone: its free iPhone slots are
# full and a free team cannot clear them. Changing this back will produce
# "maximum number of registered iPhone devices" and nothing else.
TEAM = os.environ.get("TEAM", "Z285TWPM86")

def set_team(target_name):
    for cfg in project.objects.get_configurations_on_targets(target_name):
        if cfg.buildSettings.get("DEVELOPMENT_TEAM", None) != TEAM:
            cfg.buildSettings["DEVELOPMENT_TEAM"] = TEAM
            cfg.buildSettings["CODE_SIGN_STYLE"] = "Automatic"
            changed.append(target_name + " " + cfg.name + ": team " + TEAM)


set_team("App")

# ── 3. the widget target ───────────────────────────────────────────────────
if project.get_target_by_name(WIDGET) is not None:
    print("the " + WIDGET + " target already exists — leaving it alone")
else:
    src = new(PBXFileReference, path=WIDGET + "/" + WIDGET + ".swift",
              sourceTree="<group>", lastKnownFileType="sourcecode.swift")
    plist = new(PBXFileReference, path=WIDGET + "/Info.plist",
                sourceTree="<group>", lastKnownFileType="text.plist.xml")
    ents = new(PBXFileReference, path=WIDGET + "/" + WIDGET + ".entitlements",
               sourceTree="<group>", lastKnownFileType="text.plist.entitlements")
    product = new(PBXFileReference, path=WIDGET + ".appex",
                  sourceTree="BUILT_PRODUCTS_DIR",
                  explicitFileType="wrapper.app-extension", includeInIndex="0")

    group = new(PBXGroup, name=WIDGET, sourceTree="<group>",
                children=[src.get_id(), plist.get_id(), ents.get_id()])
    pbxproject = project.objects[project["rootObject"]]
    root = project.objects[pbxproject.mainGroup]
    root.children.insert(0, group.get_id())

    # the .appex has to show up under Products or Xcode's navigator complains
    products = group_by(name="Products")
    if products is not None:
        products.children.append(product.get_id())

    compile_src = new(PBXBuildFile, fileRef=src.get_id())
    sources = new(PBXSourcesBuildPhase, files=[compile_src.get_id()],
                  buildActionMask="2147483647",
                  runOnlyForDeploymentPostprocessing="0")

    configs = []
    for name in ("Debug", "Release"):
        configs.append(new(XCBuildConfiguration, name=name,
                           buildSettings=settings(name)).get_id())
    config_list = new(XCConfigurationList, buildConfigurations=configs,
                      defaultConfigurationIsVisible="0",
                      defaultConfigurationName="Release")

    target = new(PBXNativeTarget, name=WIDGET, productName=WIDGET,
                 productReference=product.get_id(),
                 productType="com.apple.product-type.app-extension",
                 buildConfigurationList=config_list.get_id(),
                 buildPhases=[sources.get_id()],
                 buildRules=[], dependencies=[])

    pbxproject.targets.append(target.get_id())

    # ── 4. the app embeds it, and waits for it to build ──
    proxy = new(PBXContainerItemProxy, containerPortal=project["rootObject"],
                proxyType="1", remoteGlobalIDString=target.get_id(),
                remoteInfo=WIDGET)
    dep = new(PBXTargetDependency, target=target.get_id(),
              targetProxy=proxy.get_id())
    app.dependencies.append(dep.get_id())

    # fileRef, not productRef: productRef means a Swift package product to
    # Xcode 26, and the build service rejects the whole project file.
    embed_file = new(PBXBuildFile, fileRef=product.get_id(),
                     settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]})
    embed = new(PBXCopyFilesBuildPhase, name="Embed Foundation Extensions",
                dstPath="", dstSubfolderSpec="13",
                files=[embed_file.get_id()], buildActionMask="2147483647",
                runOnlyForDeploymentPostprocessing="0")
    app.buildPhases.append(embed.get_id())

    changed.append(WIDGET + " target created, embedded and made a dependency")

# ── 5. extra sources in the widget target ─────────────────────────────────
# The widget grew past one file. Adding them here rather than in Xcode means
# a re-added platform does not silently lose half the widgets — they would
# simply stop appearing in the gallery, with nothing to explain why.
widget_target = project.get_target_by_name(WIDGET)
if widget_target is not None:
    wsources = phase_of(widget_target, "PBXSourcesBuildPhase")
    wgroup = group_by(name=WIDGET)
    for extra in ("CalendarWidget.swift",):
        if project.get_files_by_name(extra):
            continue
        if wsources is None or wgroup is None:
            print("  ! cannot reach the " + WIDGET + " sources phase for " + extra)
            break
        ref = new(PBXFileReference, path=WIDGET + "/" + extra,
                  sourceTree="<group>", lastKnownFileType="sourcecode.swift")
        wgroup.children.append(ref.get_id())
        wsources.files.append(new(PBXBuildFile, fileRef=ref.get_id()).get_id())
        changed.append(extra + " added to the " + WIDGET + " target")

set_team(WIDGET)

if changed:
    project.save()
    print("project updated:")
    for line in changed:
        print("  · " + line)
else:
    print("nothing to change — the project already has the widget wired in")
