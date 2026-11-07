# Generates the Info.plist files of the application bundles which are assembled
# from the install tree by create-package.sh

if(CMAKE_OSX_DEPLOYMENT_TARGET)
	set(BUNDLE_MINIMUM_SYSTEM_VERSION ${CMAKE_OSX_DEPLOYMENT_TARGET})
else()
	set(BUNDLE_MINIMUM_SYSTEM_VERSION 12.0)
endif()

set(BUNDLE_NAME "Veyon Master")
set(BUNDLE_EXECUTABLE veyon-master)
set(BUNDLE_IDENTIFIER io.veyon.master)
set(BUNDLE_ICON veyon-master)
configure_file(Info.plist.in ${CMAKE_CURRENT_BINARY_DIR}/veyon-master.plist @ONLY)

set(BUNDLE_NAME "Veyon Configurator")
set(BUNDLE_EXECUTABLE veyon-configurator)
set(BUNDLE_IDENTIFIER io.veyon.configurator)
set(BUNDLE_ICON veyon-configurator)
configure_file(Info.plist.in ${CMAKE_CURRENT_BINARY_DIR}/veyon-configurator.plist @ONLY)

file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/version "${VERSION_MAJOR}.${VERSION_MINOR}.${VERSION_PATCH}.${VERSION_BUILD}")
