include(BuildVeyonPlugin)

find_package(PAM REQUIRED)

build_veyon_plugin(mac-platform
	NAME MacPlatform
	SOURCES
	MacPlatformPlugin.cpp
	MacCoreFunctions.cpp
	MacFilesystemFunctions.cpp
	MacInputDeviceFunctions.cpp
	MacNetworkFunctions.cpp
	MacServiceFunctions.cpp
	MacSessionFunctions.cpp
	MacUserFunctions.cpp
	MacPlatformPlugin.h
	MacCoreFunctions.h
	MacFilesystemFunctions.h
	MacInputDeviceFunctions.h
	MacKeyboardShortcutTrapper.h
	MacNetworkFunctions.h
	MacServiceFunctions.h
	MacSessionFunctions.h
	MacUserFunctions.h
)

target_include_directories(mac-platform PRIVATE ${PAM_INCLUDE_DIR})

# prevent AssertMacros.h (pulled in by system frameworks) from defining check(), verify() etc.
target_compile_definitions(mac-platform PRIVATE __ASSERT_MACROS_DEFINE_VERSIONS_WITHOUT_UNDERSCORES=0)

target_link_libraries(mac-platform PRIVATE
	Qt${QT_MAJOR_VERSION}::Network
	${PAM_LIBRARIES}
	"-framework CoreFoundation"
	"-framework IOKit"
)
