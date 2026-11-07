file(GLOB plugins RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} ${CMAKE_CURRENT_SOURCE_DIR}/*)

if(NOT WITH_SERVER)
	list(REMOVE_ITEM plugins vncserver)
endif()

if(NOT WITH_LDAP)
	list(REMOVE_ITEM plugins ldap)
endif()

foreach(plugin ${plugins})
	if(IS_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/${plugin})
		add_subdirectory(${plugin})
	endif()
endforeach()
