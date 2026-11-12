#!/usr/bin/env python3
"""Deterministic, dependency-free Xcode project generation; run after adding Swift files."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, value):
    key = uid(name); objects[key] = value; return key
def quoted(s): return '"' + s.replace('"', '\\"') + '"'
def array(xs): return '(' + ', '.join(xs) + (',' if xs else '') + ')'
def config_list(name, settings):
    ids=[]
    for mode in ['Debug','Release']:
        values=dict(settings)
        values.update({'SWIFT_OPTIMIZATION_LEVEL': '"-Onone"' if mode=='Debug' else '"-O"', 'DEBUG_INFORMATION_FORMAT': 'dwarf' if mode=='Debug' else '"dwarf-with-dsym"'})
        if mode=='Debug': values['SWIFT_ACTIVE_COMPILATION_CONDITIONS']='DEBUG'
        ids.append(add(name+mode, '{isa = XCBuildConfiguration; name = '+mode+'; buildSettings = {'+' '.join(k+' = '+v+';' for k,v in values.items())+'};}'))
    return add(name+'configs', '{isa = XCConfigurationList; buildConfigurations = '+array(ids)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}')
app_files=sorted(ROOT.glob('notchjam/**/*.swift'))
test_files=sorted(ROOT.glob('notchjamTests/*.swift'))
def files(paths):
    refs=[]; builds=[]
    for p in paths:
        rel=str(p.relative_to(ROOT))
        ref=add(rel, '{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = '+quoted(rel)+'; sourceTree = SOURCE_ROOT;}')
        refs.append(ref)
        builds.append(add('build'+rel, '{isa = PBXBuildFile; fileRef = '+ref+';}'))
    return refs,builds
apprefs,appbuild=files(app_files); testrefs,testbuild=files(test_files)
icon=add('icon', '{isa = PBXFileReference; lastKnownFileType = image.icns; path = notchjam/Resources/notchjam.icns; sourceTree = SOURCE_ROOT;}')
iconBuild=add('iconBuild', '{isa = PBXBuildFile; fileRef = '+icon+';}')
apprefs.append(icon)
appProduct=add('appProduct','{isa = PBXFileReference; explicitFileType = wrapper.application; path = notchjam.app; sourceTree = BUILT_PRODUCTS_DIR;}')
testProduct=add('testProduct','{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = notchjamTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;}')
products=add('products','{isa = PBXGroup; name = Products; children = '+array([appProduct,testProduct])+'; sourceTree = "<group>";}')
appGroup=add('appGroup','{isa = PBXGroup; name = notchjam; children = '+array(apprefs)+'; sourceTree = "<group>";}')
testGroup=add('testGroup','{isa = PBXGroup; name = notchjamTests; children = '+array(testrefs)+'; sourceTree = "<group>";}')
mainGroup=add('mainGroup','{isa = PBXGroup; children = '+array([appGroup,testGroup,products])+'; sourceTree = "<group>";}')
shared={'SDKROOT':'macosx','MACOSX_DEPLOYMENT_TARGET':'14.0','SWIFT_VERSION':'6.0','SWIFT_STRICT_CONCURRENCY':'complete','CLANG_ENABLE_MODULES':'YES','ENABLE_TESTABILITY':'YES','CODE_SIGN_STYLE':'Automatic','COMBINE_HIDPI_IMAGES':'YES'}
projectConfig=config_list('project',shared)
appConfig=config_list('app',{'PRODUCT_NAME':'notchjam','PRODUCT_BUNDLE_IDENTIFIER':'com.notchjam.app','INFOPLIST_FILE':'notchjam/Resources/Info.plist','CODE_SIGN_ENTITLEMENTS':'notchjam/Resources/notchjam.entitlements','ENABLE_HARDENED_RUNTIME':'YES','ENABLE_APP_SANDBOX':'NO','LD_RUNPATH_SEARCH_PATHS':'"$(inherited) @executable_path/../Frameworks"'})
testConfig=config_list('test',{'PRODUCT_NAME':'notchjamTests','PRODUCT_BUNDLE_IDENTIFIER':'com.notchjam.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'"$(BUILT_PRODUCTS_DIR)/notchjam.app/Contents/MacOS/notchjam"','BUNDLE_LOADER':'"$(TEST_HOST)"'})
def phase(name, kind, builds): return add(name,'{isa = '+kind+'; buildActionMask = 2147483647; files = '+array(builds)+'; runOnlyForDeploymentPostprocessing = 0;}')
appResources=phase('appResources','PBXResourcesBuildPhase',[iconBuild])
appSources=phase('appSources','PBXSourcesBuildPhase',appbuild)
testSources=phase('testSources','PBXSourcesBuildPhase',testbuild)
appFrameworks=phase('appFrameworks','PBXFrameworksBuildPhase',[])
testFrameworks=phase('testFrameworks','PBXFrameworksBuildPhase',[])
appTarget=uid('appTarget'); project=uid('project')
proxy=add('proxy','{isa = PBXContainerItemProxy; containerPortal = '+project+'; proxyType = 1; remoteGlobalIDString = '+appTarget+'; remoteInfo = notchjam;}')
dependency=add('dependency','{isa = PBXTargetDependency; target = '+appTarget+'; targetProxy = '+proxy+';}')
add('appTarget','{isa = PBXNativeTarget; buildConfigurationList = '+appConfig+'; buildPhases = '+array([appSources,appFrameworks,appResources])+'; buildRules = (); dependencies = (); name = notchjam; productName = notchjam; productReference = '+appProduct+'; productType = "com.apple.product-type.application";}')
testTarget=add('testTarget','{isa = PBXNativeTarget; buildConfigurationList = '+testConfig+'; buildPhases = '+array([testSources,testFrameworks])+'; buildRules = (); dependencies = '+array([dependency])+'; name = notchjamTests; productName = notchjamTests; productReference = '+testProduct+'; productType = "com.apple.product-type.bundle.unit-test";}')
add('project','{isa = PBXProject; attributes = {LastSwiftUpdateCheck = 1600; LastUpgradeCheck = 1600;}; buildConfigurationList = '+projectConfig+'; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = '+mainGroup+'; productRefGroup = '+products+'; projectDirPath = ""; projectRoot = ""; targets = '+array([appTarget,testTarget])+';}')
proj=ROOT/'notchjam.xcodeproj'; proj.mkdir(exist_ok=True)
(proj/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = '+v+';' for k,v in objects.items())+'\n}; rootObject = '+project+';}\n')
def ref(id,name,buildable): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{id}" BuildableName="{buildable}" BlueprintName="{name}" ReferencedContainer="container:notchjam.xcodeproj"/>'
appref=ref(appTarget,'notchjam','notchjam.app'); testref=ref(testTarget,'notchjamTests','notchjamTests.xctest')
scheme=f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{appref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{testref}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{appref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>'''
path=proj/'xcshareddata/xcschemes'; path.mkdir(parents=True,exist_ok=True)
(path/'notchjam.xcscheme').write_text(scheme)
