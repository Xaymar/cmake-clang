set(CLANG_PATH "" CACHE PATH "Path to Clang Toolset (if not in environment)")

function(clang_format)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_CLANG_FORMAT
		"DEPENDENCY;GLOBAL"
		"REGEX;VERSION"
		"TARGETS"
	)

	find_program(CLANG_FORMAT_BIN
		"clang-format"
		DOC "Path (or name) of the clang-format binary"
		HINTS
			${CLANG_PATH}
		PATHS
			/bin
			/sbin
			/usr/bin
			/usr/local/bin
		PATH_SUFFIXES
			bin
			bin64
			bin32
	)
	if(NOT CLANG_FORMAT_BIN)
		message(WARNING "Clang: Could not find clang-format at path '${CLANG_FORMAT_BIN}', disabling clang-format...")
		return()
	endif()

	# Validate Version
	if (_CLANG_FORMAT_VERSION)
		set(_VERSION_RESULT "")
		set(_VERSION_OUTPUT "")
		execute_process(
			COMMAND "${CLANG_FORMAT_BIN}" --version
			WORKING_DIRECTORY ${CMAKE_CURRENT_LIST_DIR}
			RESULT_VARIABLE _VERSION_RESULT
			OUTPUT_VARIABLE _VERSION_OUTPUT
			OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_STRIP_TRAILING_WHITESPACE ERROR_QUIET
		)
		if(NOT _VERSION_RESULT EQUAL 0)
			message(WARNING "Clang: Could not discover version, disabling clang-format...")
			return()
		endif()
		string(REGEX MATCH "([0-9]+\.[0-9]+\.[0-9]+)" _VERSION_MATCH ${_VERSION_OUTPUT})
		if(NOT ${_VERSION_MATCH} VERSION_GREATER_EQUAL ${_CLANG_FORMAT_VERSION})
			message(WARNING "Clang: Old version discovered, disabling clang-format...")
			return()
		endif()
	endif()

	# Default Filter
	if(NOT _CLANG_FORMAT_FILTER)
		set(_CLANG_FORMAT_FILTER "\.(h|hpp|c|cpp)$")
	endif()

	# Go through each target
	foreach(_target ${_CLANG_FORMAT_TARGETS})
#		get_target_property(target_name ${_target} NAME)

		get_target_property(target_sources_rel ${_target} SOURCES)
		set(target_sources "")
		foreach(source_relative ${target_sources_rel})
			get_filename_component(source_absolute ${source_relative} ABSOLUTE)
			list(APPEND target_sources ${source_absolute})
		endforeach()
		list(FILTER target_sources INCLUDE REGEX "${_CLANG_FORMAT_FILTER}")
		unset(target_sources_rel)
		
		get_target_property(target_source_dir_rel ${_target} SOURCE_DIR)
		get_filename_component(target_source_dir ${target_source_dir_rel} ABSOLUTE)
		unset(target_source_dir_rel)

		add_custom_target(${_target}_CLANG-FORMAT
			COMMAND
				${CLANG_FORMAT_BIN}
				-style=file
				-i
				${target_sources}
			COMMENT
				"clang-format: Formatting ${_target}..."
			WORKING_DIRECTORY
				${target_source_dir_rel}
		)

		if(_CLANG_FORMAT_DEPENDENCY)
			add_dependencies(${_target} ${_target}_CLANG-FORMAT)
		endif()

		if(_CLANG_FORMAT_GLOBAL)
			if(TARGET CLANG-FORMAT)
				add_dependencies(CLANG-FORMAT ${_target}_CLANG-FORMAT)
			else()
				add_custom_target(CLANG-FORMAT
					DEPENDS
						${_target}_CLANG-FORMAT
					COMMENT
						"clang-format: Formatting..."
				)
			endif()
		endif()
	endforeach()
endfunction()
