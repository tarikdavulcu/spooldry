#!/usr/bin/env python3
"""Writes ios/SpoolDry.xcodeproj (Xcode 16+/26 format with file-system synchronized groups).

Synchronized groups mean new Swift files are picked up automatically, so the project file stays tiny
and reviewable. ios/project.yml (XcodeGen) describes the same project as an alternative.
"""
import hashlib
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent / "ios"
PROJ = ROOT / "SpoolDry.xcodeproj"


def oid(name: str) -> str:
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


I = {n: oid(n) for n in [
    "project", "mainGroup", "productsGroup",
    "app.product", "widget.product", "tests.product",
    "app.target", "widget.target", "tests.target",
    "app.sources", "app.frameworks", "app.resources", "app.embed",
    "widget.sources", "widget.frameworks", "widget.resources",
    "tests.sources", "tests.frameworks", "tests.resources",
    "grp.SpoolDry", "grp.Shared", "grp.Widgets", "grp.Tests",
    "exc.app", "exc.widget",
    "kit.ref", "kit.dep.app", "kit.dep.widget", "kit.dep.tests",
    "bf.kit.app", "bf.kit.widget", "bf.kit.tests", "bf.embed.widget",
    "proxy.widget", "proxy.app", "dep.widget", "dep.app",
    "cfg.project", "cfg.project.debug", "cfg.project.release",
    "cfg.app", "cfg.app.debug", "cfg.app.release",
    "cfg.widget", "cfg.widget.debug", "cfg.widget.release",
    "cfg.tests", "cfg.tests.debug", "cfg.tests.release",
]}

COMMON_PROJECT = """				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				COPY_PHASE_STRIP = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MARKETING_VERSION = 1.0.0;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				STRING_CATALOG_GENERATE_SYMBOLS = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
"""

DEBUG_EXTRA = """				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
"""

RELEASE_EXTRA = """				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				MTL_ENABLE_DEBUG_INFO = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
"""

APP = """				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_ENTITLEMENTS = SpoolDry/Resources/SpoolDry.entitlements;
				CODE_SIGN_STYLE = Automatic;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = SpoolDry/Resources/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.tarikdavulcu.spooldry;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
"""

WIDGET = """				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				ASSETCATALOG_COMPILER_WIDGET_BACKGROUND_COLOR_NAME = WidgetBackground;
				CODE_SIGN_ENTITLEMENTS = SpoolDryWidgets/SpoolDryWidgets.entitlements;
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = SpoolDryWidgets/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
					"@executable_path/../../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.tarikdavulcu.spooldry.widgets;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SKIP_INSTALL = YES;
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = YES;
"""

TESTS = """				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.tarikdavulcu.spooldry.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SWIFT_EMIT_LOC_STRINGS = NO;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/SpoolDry.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/SpoolDry";
"""


def cfg(key, name, body):
    return f"""		{I[key]} /* {name} */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
{body}			}};
			name = {name};
		}};
"""


def build():
    o = I
    s = []
    s.append("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n\n")
    s.append("/* Begin PBXBuildFile section */\n")
    s.append(f"\t\t{o['bf.kit.app']} /* SpoolDryKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {o['kit.dep.app']} /* SpoolDryKit */; }};\n")
    s.append(f"\t\t{o['bf.kit.widget']} /* SpoolDryKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {o['kit.dep.widget']} /* SpoolDryKit */; }};\n")
    s.append(f"\t\t{o['bf.kit.tests']} /* SpoolDryKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {o['kit.dep.tests']} /* SpoolDryKit */; }};\n")
    s.append(f"\t\t{o['bf.embed.widget']} /* SpoolDryWidgets.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {o['widget.product']} /* SpoolDryWidgets.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};\n")
    s.append("/* End PBXBuildFile section */\n\n")

    s.append("/* Begin PBXContainerItemProxy section */\n")
    s.append(f"\t\t{o['proxy.widget']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {o['project']} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {o['widget.target']};\n\t\t\tremoteInfo = SpoolDryWidgets;\n\t\t}};\n")
    s.append(f"\t\t{o['proxy.app']} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {o['project']} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {o['app.target']};\n\t\t\tremoteInfo = SpoolDry;\n\t\t}};\n")
    s.append("/* End PBXContainerItemProxy section */\n\n")

    s.append("/* Begin PBXCopyFilesBuildPhase section */\n")
    s.append(f"\t\t{o['app.embed']} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{o['bf.embed.widget']} /* SpoolDryWidgets.appex in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXCopyFilesBuildPhase section */\n\n")

    s.append("/* Begin PBXFileReference section */\n")
    s.append(f"\t\t{o['app.product']} /* SpoolDry.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SpoolDry.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    s.append(f"\t\t{o['widget.product']} /* SpoolDryWidgets.appex */ = {{isa = PBXFileReference; explicitFileType = \"wrapper.app-extension\"; includeInIndex = 0; path = SpoolDryWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    s.append(f"\t\t{o['tests.product']} /* SpoolDryTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = SpoolDryTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};\n")
    s.append("/* End PBXFileReference section */\n\n")

    s.append("/* Begin PBXFileSystemSynchronizedBuildFileExceptionSet section */\n")
    s.append(f"\t\t{o['exc.app']} /* Exceptions for \"SpoolDry\" folder in \"SpoolDry\" target */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n\t\t\t\tResources/Info.plist,\n\t\t\t\tResources/SpoolDry.entitlements,\n\t\t\t\tResources/SpoolDry.storekit,\n\t\t\t);\n\t\t\ttarget = {o['app.target']} /* SpoolDry */;\n\t\t}};\n")
    s.append(f"\t\t{o['exc.widget']} /* Exceptions for \"SpoolDryWidgets\" folder in \"SpoolDryWidgets\" target */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedBuildFileExceptionSet;\n\t\t\tmembershipExceptions = (\n\t\t\t\tInfo.plist,\n\t\t\t\tSpoolDryWidgets.entitlements,\n\t\t\t);\n\t\t\ttarget = {o['widget.target']} /* SpoolDryWidgets */;\n\t\t}};\n")
    s.append("/* End PBXFileSystemSynchronizedBuildFileExceptionSet section */\n\n")

    s.append("/* Begin PBXFileSystemSynchronizedRootGroup section */\n")
    s.append(f"\t\t{o['grp.SpoolDry']} /* SpoolDry */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\texceptions = (\n\t\t\t\t{o['exc.app']} /* Exceptions for \"SpoolDry\" folder in \"SpoolDry\" target */,\n\t\t\t);\n\t\t\tpath = SpoolDry;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append(f"\t\t{o['grp.Shared']} /* Shared */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = Shared;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append(f"\t\t{o['grp.Widgets']} /* SpoolDryWidgets */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\texceptions = (\n\t\t\t\t{o['exc.widget']} /* Exceptions for \"SpoolDryWidgets\" folder in \"SpoolDryWidgets\" target */,\n\t\t\t);\n\t\t\tpath = SpoolDryWidgets;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append(f"\t\t{o['grp.Tests']} /* SpoolDryTests */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = SpoolDryTests;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append("/* End PBXFileSystemSynchronizedRootGroup section */\n\n")

    s.append("/* Begin PBXFrameworksBuildPhase section */\n")
    for t, bf in (("app", "bf.kit.app"), ("widget", "bf.kit.widget"), ("tests", "bf.kit.tests")):
        s.append(f"\t\t{o[t + '.frameworks']} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t\t{o[bf]} /* SpoolDryKit in Frameworks */,\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXFrameworksBuildPhase section */\n\n")

    s.append("/* Begin PBXGroup section */\n")
    s.append(f"\t\t{o['mainGroup']} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{o['grp.SpoolDry']} /* SpoolDry */,\n\t\t\t\t{o['grp.Shared']} /* Shared */,\n\t\t\t\t{o['grp.Widgets']} /* SpoolDryWidgets */,\n\t\t\t\t{o['grp.Tests']} /* SpoolDryTests */,\n\t\t\t\t{o['productsGroup']} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append(f"\t\t{o['productsGroup']} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{o['app.product']} /* SpoolDry.app */,\n\t\t\t\t{o['widget.product']} /* SpoolDryWidgets.appex */,\n\t\t\t\t{o['tests.product']} /* SpoolDryTests.xctest */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")
    s.append("/* End PBXGroup section */\n\n")

    s.append("/* Begin PBXNativeTarget section */\n")
    s.append(f"""		{o['app.target']} /* SpoolDry */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {o['cfg.app']} /* Build configuration list for PBXNativeTarget "SpoolDry" */;
			buildPhases = (
				{o['app.sources']} /* Sources */,
				{o['app.frameworks']} /* Frameworks */,
				{o['app.resources']} /* Resources */,
				{o['app.embed']} /* Embed Foundation Extensions */,
			);
			buildRules = (
			);
			dependencies = (
				{o['dep.widget']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{o['grp.SpoolDry']} /* SpoolDry */,
				{o['grp.Shared']} /* Shared */,
			);
			name = SpoolDry;
			packageProductDependencies = (
				{o['kit.dep.app']} /* SpoolDryKit */,
			);
			productName = SpoolDry;
			productReference = {o['app.product']} /* SpoolDry.app */;
			productType = "com.apple.product-type.application";
		}};
		{o['widget.target']} /* SpoolDryWidgets */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {o['cfg.widget']} /* Build configuration list for PBXNativeTarget "SpoolDryWidgets" */;
			buildPhases = (
				{o['widget.sources']} /* Sources */,
				{o['widget.frameworks']} /* Frameworks */,
				{o['widget.resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				{o['grp.Widgets']} /* SpoolDryWidgets */,
				{o['grp.Shared']} /* Shared */,
			);
			name = SpoolDryWidgets;
			packageProductDependencies = (
				{o['kit.dep.widget']} /* SpoolDryKit */,
			);
			productName = SpoolDryWidgets;
			productReference = {o['widget.product']} /* SpoolDryWidgets.appex */;
			productType = "com.apple.product-type.app-extension";
		}};
		{o['tests.target']} /* SpoolDryTests */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {o['cfg.tests']} /* Build configuration list for PBXNativeTarget "SpoolDryTests" */;
			buildPhases = (
				{o['tests.sources']} /* Sources */,
				{o['tests.frameworks']} /* Frameworks */,
				{o['tests.resources']} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				{o['dep.app']} /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				{o['grp.Tests']} /* SpoolDryTests */,
			);
			name = SpoolDryTests;
			packageProductDependencies = (
				{o['kit.dep.tests']} /* SpoolDryKit */,
			);
			productName = SpoolDryTests;
			productReference = {o['tests.product']} /* SpoolDryTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		}};
""")
    s.append("/* End PBXNativeTarget section */\n\n")

    s.append("/* Begin PBXProject section */\n")
    s.append(f"""		{o['project']} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2600;
				LastUpgradeCheck = 2600;
				TargetAttributes = {{
					{o['app.target']} = {{
						CreatedOnToolsVersion = 26.0;
					}};
					{o['widget.target']} = {{
						CreatedOnToolsVersion = 26.0;
					}};
					{o['tests.target']} = {{
						CreatedOnToolsVersion = 26.0;
						TestTargetID = {o['app.target']};
					}};
				}};
			}};
			buildConfigurationList = {o['cfg.project']} /* Build configuration list for PBXProject "SpoolDry" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
				de,
				fr,
				es,
				ar,
				ja,
			);
			mainGroup = {o['mainGroup']};
			minimizedProjectReferenceProxies = 1;
			packageReferences = (
				{o['kit.ref']} /* XCLocalSwiftPackageReference "Packages/SpoolDryKit" */,
			);
			preferredProjectObjectVersion = 77;
			productRefGroup = {o['productsGroup']} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{o['app.target']} /* SpoolDry */,
				{o['widget.target']} /* SpoolDryWidgets */,
				{o['tests.target']} /* SpoolDryTests */,
			);
		}};
""")
    s.append("/* End PBXProject section */\n\n")

    s.append("/* Begin PBXResourcesBuildPhase section */\n")
    for t in ("app", "widget", "tests"):
        s.append(f"\t\t{o[t + '.resources']} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXResourcesBuildPhase section */\n\n")

    s.append("/* Begin PBXSourcesBuildPhase section */\n")
    for t in ("app", "widget", "tests"):
        s.append(f"\t\t{o[t + '.sources']} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
    s.append("/* End PBXSourcesBuildPhase section */\n\n")

    s.append("/* Begin PBXTargetDependency section */\n")
    s.append(f"\t\t{o['dep.widget']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {o['widget.target']} /* SpoolDryWidgets */;\n\t\t\ttargetProxy = {o['proxy.widget']} /* PBXContainerItemProxy */;\n\t\t}};\n")
    s.append(f"\t\t{o['dep.app']} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {o['app.target']} /* SpoolDry */;\n\t\t\ttargetProxy = {o['proxy.app']} /* PBXContainerItemProxy */;\n\t\t}};\n")
    s.append("/* End PBXTargetDependency section */\n\n")

    s.append("/* Begin XCBuildConfiguration section */\n")
    s.append(cfg("cfg.project.debug", "Debug", COMMON_PROJECT + DEBUG_EXTRA))
    s.append(cfg("cfg.project.release", "Release", COMMON_PROJECT + RELEASE_EXTRA))
    s.append(cfg("cfg.app.debug", "Debug", APP))
    s.append(cfg("cfg.app.release", "Release", APP))
    s.append(cfg("cfg.widget.debug", "Debug", WIDGET))
    s.append(cfg("cfg.widget.release", "Release", WIDGET))
    s.append(cfg("cfg.tests.debug", "Debug", TESTS))
    s.append(cfg("cfg.tests.release", "Release", TESTS))
    s.append("/* End XCBuildConfiguration section */\n\n")

    s.append("/* Begin XCConfigurationList section */\n")
    for key, kind, name in (("cfg.project", "PBXProject", "SpoolDry"), ("cfg.app", "PBXNativeTarget", "SpoolDry"),
                            ("cfg.widget", "PBXNativeTarget", "SpoolDryWidgets"), ("cfg.tests", "PBXNativeTarget", "SpoolDryTests")):
        s.append(f"\t\t{o[key]} /* Build configuration list for {kind} \"{name}\" */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{o[key + '.debug']} /* Debug */,\n\t\t\t\t{o[key + '.release']} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};\n")
    s.append("/* End XCConfigurationList section */\n\n")

    s.append("/* Begin XCLocalSwiftPackageReference section */\n")
    s.append(f"\t\t{o['kit.ref']} /* XCLocalSwiftPackageReference \"Packages/SpoolDryKit\" */ = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = Packages/SpoolDryKit;\n\t\t}};\n")
    s.append("/* End XCLocalSwiftPackageReference section */\n\n")

    s.append("/* Begin XCSwiftPackageProductDependency section */\n")
    for k in ("kit.dep.app", "kit.dep.widget", "kit.dep.tests"):
        s.append(f"\t\t{o[k]} /* SpoolDryKit */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tpackage = {o['kit.ref']} /* XCLocalSwiftPackageReference \"Packages/SpoolDryKit\" */;\n\t\t\tproductName = SpoolDryKit;\n\t\t}};\n")
    s.append("/* End XCSwiftPackageProductDependency section */\n")
    s.append(f"\t}};\n\trootObject = {o['project']} /* Project object */;\n}}\n")
    return "".join(s)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "2600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES" buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app}" BuildableName = "SpoolDry.app" BlueprintName = "SpoolDry" ReferencedContainer = "container:SpoolDry.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES" shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference skipped = "NO" parallelizable = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{tests}" BuildableName = "SpoolDryTests.xctest" BlueprintName = "SpoolDryTests" ReferencedContainer = "container:SpoolDry.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app}" BuildableName = "SpoolDry.app" BlueprintName = "SpoolDry" ReferencedContainer = "container:SpoolDry.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference identifier = "../../SpoolDry/Resources/SpoolDry.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app}" BuildableName = "SpoolDry.app" BlueprintName = "SpoolDry" ReferencedContainer = "container:SpoolDry.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


def main():
    PROJ.mkdir(parents=True, exist_ok=True)
    (PROJ / "project.pbxproj").write_text(build())
    sd = PROJ / "xcshareddata" / "xcschemes"
    sd.mkdir(parents=True, exist_ok=True)
    (sd / "SpoolDry.xcscheme").write_text(SCHEME.format(app=I["app.target"], tests=I["tests.target"]))
    ws = PROJ / "project.xcworkspace"
    ws.mkdir(exist_ok=True)
    (ws / "contents.xcworkspacedata").write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')
    print("wrote", PROJ)


if __name__ == "__main__":
    main()
