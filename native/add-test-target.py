#!/usr/bin/env python3
"""Add the AppTests unit-test target: purchases and entitlements, tested against Do.storekit.

What it does to the project, once (it is safe to run again):

  AppTests target   a unit-test bundle hosted by the app, so the tests reach
                    the real Store class with @testable import App
                    + AppTests/StoreTests.swift in its Sources
                    + App/Do.storekit in its Resources (SKTestSession reads it)
  App scheme        + AppTests under Test, so `xcodebuild test` runs it

Run with the venv python that has pbxproj:
    ./.tools/bin/python add-test-target.py
"""

import pathlib
import re
import sys

from pbxproj import XcodeProject
from pbxproj.pbxsections import (PBXBuildFile, PBXContainerItemProxy, PBXFileReference,
                                 PBXFrameworksBuildPhase, PBXGroup, PBXNativeTarget,
                                 PBXResourcesBuildPhase, PBXSourcesBuildPhase,
                                 PBXTargetDependency, XCBuildConfiguration,
                                 XCConfigurationList)

HERE = pathlib.Path(__file__).resolve().parent
PROJ = HERE / "ios" / "App" / "App.xcodeproj" / "project.pbxproj"
SCHEME = HERE / "ios" / "App" / "App.xcodeproj" / "xcshareddata" / "xcschemes" / "App.xcscheme"
NAME = "AppTests"
APP_ID = "io.github.do-productivity.do"
TEAM = "6MCMG3FEW8"

project = XcodeProject.load(str(PROJ))


def new(cls, **fields):
    fields["_id"] = cls._generate_id()
    fields["isa"] = cls.__name__
    obj = cls().parse(fields)
    project.objects[obj.get_id()] = obj
    return obj


def group_by(name=None, path=None):
    for g in project.objects.get_objects_in_section("PBXGroup"):
        if name is not None and getattr(g, "name", None) == name:
            return g
        if path is not None and getattr(g, "path", None) == path:
            return g
    return None


app = project.get_target_by_name("App")
if app is None:
    sys.exit("no target called App in the project")

if project.get_target_by_name(NAME) is None:
    root = project.objects[project.rootObject]
    main_group = project.objects[root.mainGroup]

    # the test source, in a group of its own
    tests_group = new(PBXGroup, path=NAME, sourceTree="<group>", children=[])
    main_group.children.append(tests_group.get_id())
    swift = new(PBXFileReference, path="StoreTests.swift", sourceTree="<group>",
                lastKnownFileType="sourcecode.swift")
    tests_group.children.append(swift.get_id())

    # the StoreKit configuration, shown in the App group but built only into the tests
    storekit = None
    for f in project.objects.get_objects_in_section("PBXFileReference"):
        if getattr(f, "path", None) == "Do.storekit":
            storekit = f
    if storekit is None:
        app_group = group_by(path="App")
        storekit = new(PBXFileReference, path="Do.storekit", sourceTree="<group>",
                       lastKnownFileType="text")
        app_group.children.append(storekit.get_id())

    product = new(PBXFileReference, path=NAME + ".xctest", sourceTree="BUILT_PRODUCTS_DIR",
                  explicitFileType="wrapper.cfbundle", includeInIndex="0")
    products = group_by(name="Products")
    if products is not None:
        products.children.append(product.get_id())

    sources = new(PBXSourcesBuildPhase, buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0",
                  files=[new(PBXBuildFile, fileRef=swift.get_id()).get_id()])
    frameworks = new(PBXFrameworksBuildPhase, buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0", files=[])
    resources = new(PBXResourcesBuildPhase, buildActionMask="2147483647", runOnlyForDeploymentPostprocessing="0",
                    files=[new(PBXBuildFile, fileRef=storekit.get_id()).get_id()])

    def config(name):
        s = {
            "BUNDLE_LOADER": "$(TEST_HOST)",
            "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/App.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/App",
            "CODE_SIGN_STYLE": "Automatic",
            "DEVELOPMENT_TEAM": TEAM,
            "GENERATE_INFOPLIST_FILE": "YES",
            "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
            "PRODUCT_BUNDLE_IDENTIFIER": APP_ID + "." + NAME,
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1",
            "SDKROOT": "iphoneos",
        }
        if name == "Debug":
            s["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG"
            s["SWIFT_OPTIMIZATION_LEVEL"] = "-Onone"
        return new(XCBuildConfiguration, name=name, buildSettings=s)

    configs = new(XCConfigurationList, buildConfigurations=[config("Debug").get_id(), config("Release").get_id()],
                  defaultConfigurationIsVisible="0", defaultConfigurationName="Release")

    proxy = new(PBXContainerItemProxy, containerPortal=root.get_id(), proxyType="1",
                remoteGlobalIDString=app.get_id(), remoteInfo="App")
    dependency = new(PBXTargetDependency, target=app.get_id(), targetProxy=proxy.get_id())

    target = new(PBXNativeTarget, name=NAME, productName=NAME, productReference=product.get_id(),
                 productType="com.apple.product-type.bundle.unit-test",
                 buildConfigurationList=configs.get_id(),
                 buildPhases=[sources.get_id(), frameworks.get_id(), resources.get_id()],
                 buildRules=[], dependencies=[dependency.get_id()])
    root.targets.append(target.get_id())
    project.save()
    print("added the", NAME, "target")
else:
    print(NAME, "target already there")

# ── the scheme runs it ─────────────────────────────────────────────────────
target = project.get_target_by_name(NAME)
scheme = SCHEME.read_text(encoding="utf-8")
if NAME not in scheme:
    ref = '''      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "%s"
               BuildableName = "%s.xctest"
               BlueprintName = "%s"
               ReferencedContainer = "container:App.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
''' % (target.get_id(), NAME, NAME)
    scheme, n = re.subn(r'(<TestAction\b[^>]*>\n)', lambda m: m.group(1) + ref, scheme, count=1)
    if n != 1:
        sys.exit("could not find the TestAction in the scheme")
    SCHEME.write_text(scheme, encoding="utf-8")
    print("scheme runs", NAME)
else:
    print("scheme already runs", NAME)
