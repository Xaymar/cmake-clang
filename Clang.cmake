cmake_minimum_required(VERSION 3.20)

set(CLANG_PATH "" CACHE PATH "Path to Clang Toolset (if not in environment)")

function(json_escape_string)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		""
		"OUTPUT;INPUT"
		""
	)

	set(_tmp "${_ARGS_INPUT}")
	string(REPLACE "\\" "\\\\" _tmp "${_tmp}")
	string(REPLACE "\"" "\\\"" _tmp "${_tmp}")
	set(${_ARGS_OUTPUT} "${_tmp}" PARENT_SCOPE)
endfunction()

function(get_target_include_directories)
	unset(_ARGS)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"INTERFACE"
		"TARGET;OUTPUT"
		"IGNORE"
	)

	# FIXME: For some reason, CMake claims that the target we depend on depends on the target we are.
	# Might be something broken with LINK_LIBRARIES or similar?

	set(out "")
	set(ignore "${_ARGS_IGNORE}")
	list(APPEND ignore "${_ARGS_TARGET}")

	set(gtid "")
	if(_ARGS_INTERFACE)
		get_property(gtid TARGET ${current_target} PROPERTY INTERFACE_LINK_LIBRARIES)
	else()
		get_property(gtid TARGET ${current_target} PROPERTY LINK_LIBRARIES)
	endif()
	foreach(_tmp ${gtid})
		list(APPEND ignore "${_tmp}")
		if((NOT "${_tmp}" IN_LIST _ARGS_IGNORE) AND (NOT "${_tmp}" STREQUAL "${_ARGS_TARGET}") AND (TARGET "${_tmp}"))
			get_target_include_directories(INTERFACE OUTPUT _tmp2 TARGET "${_tmp}" IGNORE ${ignore})
			foreach(_tmp3 ${_tmp2})
				list(APPEND out "${_tmp3}")
			endforeach()
		endif()
	endforeach()

	set(gtid_source_dir "")
	get_property(gtid_source_dir TARGET ${_ARGS_TARGET} PROPERTY SOURCE_DIR)

	set(gtid "")
	if(_ARGS_INTERFACE)
		get_property(gtid TARGET ${_ARGS_TARGET} PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
	else()
		get_property(gtid TARGET ${_ARGS_TARGET} PROPERTY INCLUDE_DIRECTORIES)
	endif()
	foreach(_tmp ${gtid})
		cmake_path(ABSOLUTE_PATH _tmp BASE_DIRECTORY "${gtid_source_dir}")
		list(APPEND out "${_tmp}")
	endforeach()

	if(_ARGS_INTERFACE)
		set(gtid "")
		get_property(gtid TARGET ${_ARGS_TARGET} PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES)
		foreach(_tmp ${gtid})
			cmake_path(ABSOLUTE_PATH _tmp BASE_DIRECTORY "${gtid_source_dir}")
			list(APPEND out "${_tmp}")
		endforeach()
	endif()

	set(${_ARGS_OUTPUT} "${out}" PARENT_SCOPE)
endfunction()

function(get_target_definitions)
	unset(_ARGS)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"INTERFACE"
		"TARGET;OUTPUT"
		"IGNORE"
	)

	# FIXME: For some reason, CMake claims that the target we depend on depends on the target we are.
	# Might be something broken with LINK_LIBRARIES or similar?

	set(out "")
	set(ignore "${_ARGS_IGNORE}")
	list(APPEND ignore "${_ARGS_TARGET}")

	set(gtd "")
	if(_ARGS_INTERFACE)
		get_property(gtd TARGET ${current_target} PROPERTY INTERFACE_LINK_LIBRARIES)
	else()
		get_property(gtd TARGET ${current_target} PROPERTY LINK_LIBRARIES)
	endif()
	foreach(_tmp ${gtd})
		list(APPEND ignore "${_tmp}")
		if((NOT "${_tmp}" IN_LIST _ARGS_IGNORE) AND (NOT "${_tmp}" STREQUAL "${_ARGS_TARGET}") AND (TARGET "${_tmp}"))
			get_target_definitions(INTERFACE OUTPUT _tmp2 TARGET "${_tmp}" IGNORE ${ignore})
			foreach(_tmp3 ${_tmp2})
				list(APPEND out "${_tmp3}")
			endforeach()
		endif()
	endforeach()

	set(gtid "")
	if(_ARGS_INTERFACES)
		get_property(gtid TARGET ${_ARGS_TARGET} PROPERTY INTERFACE_COMPILE_DEFINITIONS)
	else()
		get_property(gtid TARGET ${_ARGS_TARGET} PROPERTY COMPILE_DEFINITIONS)
	endif()
	foreach(_tmp ${gtid})
		list(APPEND out "${_tmp}")
	endforeach()

	set(${_ARGS_OUTPUT} "${out}" PARENT_SCOPE)
endfunction()

function(generate_compile_commands_json)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		""
		"REGEX"
		"TARGETS"
	)
	if(NOT _ARGS_REGEX)
		set(_ARGS_REGEX "\.(h|hpp|c|cpp)$")
	endif()

	# If the generator itself can create the compile_commands.json file, don't create our own.
	set(cc_generators
		"Borland Makefiles"
		"MSYS Makefiles"
		"MinGW Makefiles"
		"NMake Makefiles"
		"NMake Makefiles JOM"
		"Unix Makefiles"
		"Watcom WMake"
		"Ninja"
		"Ninja Multi-Config"
	)
	if(CMAKE_GENERATOR IN_LIST cc_generators)
		foreach(current_target in ${_ARGS_TARGETS})
			set_target_properties(${current_target} PROPERTIES
				CMAKE_EXPORT_COMPILE_COMMANDS ON
			)
		endforeach()
		return()
	endif()

	# Is this generator able to have multiple configurations?
	get_property(cc_multiconfig GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
	if(NOT cc_multiconfig)
		set(cc_configurations ${CMAKE_BUILD_TYPE})
	else()
		set(cc_configurations ${CMAKE_CONFIGURATION_TYPES})
	endif()


	foreach(current_target ${_ARGS_TARGETS})
		# For each target, generate a compile_commands.json file with all files.

		# Get source and binary directory.
		get_property(cc_tgt_source_dir TARGET ${current_target} PROPERTY SOURCE_DIR)
		get_filename_component(cc_tgt_source_dir "${cc_tgt_source_dir}" ABSOLUTE)
		get_property(cc_tgt_binary_dir TARGET ${current_target} PROPERTY BINARY_DIR)
		get_filename_component(cc_tgt_binary_dir "${cc_tgt_binary_dir}" ABSOLUTE)

		# C++ Standard
		get_property(cc_tgt_std_CXX TARGET ${current_target} PROPERTY CXX_STANDARD)
		if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
			if(cc_tgt_std_CXX EQUAL 23)
				set(cc_tgt_std_CXX "/std:c++latest")
			elseif(cc_tgt_std_CXX EQUAL 20)
				set(cc_tgt_std_CXX "/std:c++20")
			elseif(cc_tgt_std_CXX EQUAL 17)
				set(cc_tgt_std_CXX "/std:c++17")
			elseif(cc_tgt_std_CXX EQUAL 14)
				set(cc_tgt_std_CXX "/std:c++14")
			else()
				set(cc_tgt_std_CXX "")
			endif()
		else()
			if(cc_tgt_std_CXX EQUAL 23)
				set(cc_tgt_std_CXX "-std=c++23")
			elseif(cc_tgt_std_CXX EQUAL 20)
				set(cc_tgt_std_CXX "-std=c++20")
			elseif(cc_tgt_std_CXX EQUAL 17)
				set(cc_tgt_std_CXX "-std=c++17")
			elseif(cc_tgt_std_CXX EQUAL 14)
				set(cc_tgt_std_CXX "-std=c++14")
			elseif(cc_tgt_std_CXX EQUAL 11)
				set(cc_tgt_std_CXX "-std=c++11")
			elseif(cc_tgt_std_CXX EQUAL 98)
				set(cc_tgt_std_CXX "-std=c++98")
			else()
				set(cc_tgt_std_CXX "")
			endif()
		endif()

		# C standard
		get_property(cc_tgt_std_C TARGET ${current_target} PROPERTY C_STANDARD)
		if(CMAKE_C_COMPILER_ID STREQUAL "MSVC")
			if(cc_tgt_std_C EQUAL 17)
				set(cc_tgt_std_C "/std:c17")
			elseif(cc_tgt_std_C EQUAL 11)
				set(cc_tgt_std_C "/std:c11")
			else()
				set(cc_tgt_std_C "")
			endif()
		else()
			if(cc_tgt_std_C EQUAL 23)
				set(cc_tgt_std_C "-std=c2x")
			elseif(cc_tgt_std_C EQUAL 17)
				set(cc_tgt_std_C "-std=c17")
			elseif(cc_tgt_std_C EQUAL 11)
				set(cc_tgt_std_C "-std=c11")
			elseif(cc_tgt_std_C EQUAL 99)
				set(cc_tgt_std_C "-std=c99")
			elseif(cc_tgt_std_C EQUAL 90)
				set(cc_tgt_std_C "-std=c90")
			else()
				set(cc_tgt_std_C "")
			endif()
		endif()

		# Include Directories
		get_property(_tmp TARGET ${current_target} PROPERTY INCLUDE_DIRECTORIES)
		foreach(_tmp2 ${_tmp})
			cmake_path(ABSOLUTE_PATH _tmp2 BASE_DIRECTORY "${cc_tgt_source_dir}")
			list(APPEND cc_tgt_includes "${_tmp2}")
		endforeach()
		get_target_include_directories(OUTPUT _tmp TARGET ${current_target})

		# Definitions, Options
		get_target_definitions(OUTPUT cc_tgt_definitions TARGET ${current_target})
		get_property(cc_tgt_options TARGET ${current_target} PROPERTY COMPILE_OPTIONS)

		# Interface stuff from link dependencies
		get_property(cc_tgt_depends TARGET ${current_target} PROPERTY LINK_LIBRARIES)
		foreach(_tmp3 ${cc_tgt_depends})
			if(TARGET ${_tmp3})
				# - Interface Include Directories
				get_property(_tmp TARGET ${_tmp3} PROPERTY INTERFACE_INCLUDE_DIRECTORIES)
				foreach(_tmp2 ${_tmp})
					cmake_path(ABSOLUTE_PATH _tmp2 BASE_DIRECTORY "${cc_tgt_source_dir}")
					list(APPEND cc_tgt_includes "${_tmp2}")
				endforeach()
				get_property(_tmp TARGET ${_tmp3} PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES)
				foreach(_tmp2 ${_tmp})
					cmake_path(ABSOLUTE_PATH _tmp2 BASE_DIRECTORY "${cc_tgt_source_dir}")
					list(APPEND cc_tgt_includes "${_tmp2}")
				endforeach()

				# - Interface Defines, Options
				get_property(_tmp TARGET ${current_target} PROPERTY INTERFACE_COMPILE_DEFINITIONS)
				foreach(_tmp2 ${_tmp})
					list(APPEND cc_tgt_definitions "${_tmp2}")
				endforeach()
				get_property(_tmp TARGET ${current_target} PROPERTY INTERFACE_COMPILE_OPTIONS)
				foreach(_tmp2 ${_tmp})
					list(APPEND cc_tgt_options "${_tmp2}")
				endforeach()
			endif()
		endforeach()

		# Figure out source files for this target.
		set(cc_tgt_sources "")
		get_target_property(_tmp ${current_target} SOURCES)
		foreach(_tmp2 ${_tmp})
			cmake_path(ABSOLUTE_PATH _tmp2 BASE_DIRECTORY "${cc_tgt_source_dir}")
			list(APPEND cc_tgt_sources "${_tmp2}")
		endforeach()
		list(FILTER cc_tgt_sources INCLUDE REGEX "${_ARGS_REGEX}")

		# Generate a unique compile_commands.json.
		set(cc_json_content "")
		string(APPEND cc_json_content "[\n")

		# Write entries for each file.
		foreach(current_source ${cc_tgt_sources})
			# Find the real location of the source file.
			get_property(cc_src_location SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY LOCATION)
			cmake_path(ABSOLUTE_PATH cc_src_location BASE_DIRECTORY "${cc_tgt_source_dir}")

			# Try and figure out the language used.
			get_property(cc_src_language SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY LANGUAGE)
			if("${cc_src_language}" STREQUAL "")
				get_filename_component(_tmp "${current_source}" EXT)
				if((_tmp STREQUAL ".hpp") OR (_tmp STREQUAL ".cpp"))
					set(cc_src_language "CXX")
				else()
					set(cc_src_language "C")
				endif()
			endif()
			if(CMAKE_${cc_src_language}_COMPILER_ID STREQUAL "MSVC")
				set(_define_prefix "/D")
				set(_include_prefix "/I")
			else()
				set(_define_prefix "-D")
				set(_include_prefix "-I")
			endif()

			if(cc_src_language STREQUAL "CXX")
				# C++ Standard
				get_property(cc_src_std_CXX SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY CXX_STANDARD)
				if(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
					if(cc_src_std_CXX EQUAL 23)
						set(cc_src_std "/std:c++latest")
					elseif(cc_src_std_CXX EQUAL 20)
						set(cc_src_std "/std:c++20")
					elseif(cc_src_std_CXX EQUAL 17)
						set(cc_src_std "/std:c++17")
					elseif(cc_src_std_CXX EQUAL 14)
						set(cc_src_std "/std:c++14")
					else()
						set(cc_src_std "${cc_tgt_std_CXX}")
					endif()
				else()
					if(cc_src_std_CXX EQUAL 23)
						set(cc_src_std "-std=c++23")
					elseif(cc_src_std_CXX EQUAL 20)
						set(cc_src_std "-std=c++20")
					elseif(cc_src_std_CXX EQUAL 17)
						set(cc_src_std "-std=c++17")
					elseif(cc_src_std_CXX EQUAL 14)
						set(cc_src_std "-std=c++14")
					elseif(cc_src_std_CXX EQUAL 11)
						set(cc_src_std "-std=c++11")
					elseif(cc_src_std_CXX EQUAL 98)
						set(cc_src_std "-std=c++98")
					else()
						set(cc_src_std "${cc_tgt_std_CXX}")
					endif()
				endif()
			else()
				# C standard
				get_property(cc_src_std_C SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY C_STANDARD)
				if(CMAKE_C_COMPILER_ID STREQUAL "MSVC")
					if(cc_src_std_C EQUAL 17)
						set(cc_src_std "/std:c17")
					elseif(cc_src_std_C EQUAL 11)
						set(cc_src_std "/std:c11")
					else()
						set(cc_src_std "${cc_tgt_std_C}")
					endif()
				else()
					if(cc_src_std_C EQUAL 23)
						set(cc_src_std "-std=c2x")
					elseif(cc_src_std_C EQUAL 17)
						set(cc_src_std "-std=c17")
					elseif(cc_src_std_C EQUAL 11)
						set(cc_src_std "-std=c11")
					elseif(cc_src_std_C EQUAL 99)
						set(cc_src_std "-std=c99")
					elseif(cc_src_std_C EQUAL 90)
						set(cc_src_std "-std=c90")
					else()
						set(cc_src_std "${cc_tgt_std_C}")
					endif()
				endif()
			endif()

			# Includes
			set(cc_src_includex "${cc_tgt_includes}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY INCLUDE_DIRECTORIES)
			foreach(_tmp2 ${_tmp})
				cmake_path(ABSOLUTE_PATH _tmp2 BASE_DIRECTORY "${cc_tgt_source_dir}")
				list(APPEND cc_src_includex "${_tmp2}")
			endforeach()

			# Defines
			set(cc_src_defines "${cc_tgt_defines}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY COMPILE_DEFINITIONS)
			foreach(_tmp2 ${_tmp})
				list(APPEND cc_src_defines "${_tmp2}")
			endforeach()

			# Compile Options
			set(cc_src_options "${cc_tgt_options}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY COMPILE_OPTIONS)
			foreach(_tmp2 ${_tmp})
				list(APPEND cc_src_options "${_tmp2}")
			endforeach()

			#get_property(_ SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY _)

			# Generate JSON content.
			string(APPEND cc_json_content "\t{\n")

			# Working Directory
			json_escape_string(OUTPUT _tmp INPUT "${cc_tgt_source_dir}")
			file(TO_CMAKE_PATH "${_tmp}" _tmp)
			string(APPEND cc_json_content "\t\t\"directory\": \"${_tmp}\",\n")

			# Target File
			json_escape_string(OUTPUT _tmp INPUT "${cc_src_location}")
			file(TO_CMAKE_PATH "${_tmp}" _tmp)
			string(APPEND cc_json_content "\t\t\"file\": \"${_tmp}\",\n")

			if(ON) # Command
				set(_tmp2 "")

				# cl/cc difference
				if(CMAKE_${cc_src_language}_COMPILER_ID STREQUAL "MSVC")
					string(APPEND _tmp2 "cl ")
				else()
					string(APPEND _tmp2 "cc ")
				endif()

				# C/CXX Standard
				string(APPEND _tmp2 "${cc_src_std} ")

				# Global Flags
				string(APPEND _tmp2 "${CMAKE_${cc_src_language}_FLAGS} ")
				foreach(current_config ${cc_configurations})
					string(TOUPPER "${current_config}" _tmp)
					string(APPEND _tmp2 "$<$<CONFIG:${current_config}>:${CMAKE_${cc_src_language}_FLAGS_${_tmp}}> ")
				endforeach()

				# Include Directories
				foreach(_tmp ${cc_src_includex})
					file(TO_CMAKE_PATH "${_tmp}" _tmp)
					json_escape_string(OUTPUT _tmp INPUT "${_tmp}")
					string(APPEND _tmp2 "\"${_include_prefix}${_tmp}\" ")
				endforeach()

				# Definitions
				foreach(_tmp ${cc_src_defines})
					json_escape_string(OUTPUT _tmp INPUT "${_tmp}")
					string(APPEND _tmp2 "\"${_define_prefix}${_tmp}\" ")
				endforeach()

				# Other Options
				foreach(_tmp ${cc_src_options})
					json_escape_string(OUTPUT _tmp INPUT "${_tmp}")
					string(APPEND _tmp2 "\"${_tmp}\" ")
				endforeach()

				# File to compile
				json_escape_string(OUTPUT _tmp INPUT "${cc_src_location}")
				if(CMAKE_${cc_src_language}_COMPILER_ID STREQUAL "MSVC")
					string(APPEND _tmp2 "\"${_tmp}\"")
				else()
					string(APPEND _tmp2 "-c \"${_tmp}\"")
				endif()

				# Command
				json_escape_string(OUTPUT _tmp INPUT "${_tmp2}")
				string(APPEND cc_json_content "\t\t\"command\": \"${_tmp}\"\n")
			endif()

			string(APPEND cc_json_content "\t},\n")
		endforeach()

		# Close the array.
		string(APPEND cc_json_content "]\n")

		# Generate file
		file(GENERATE
			OUTPUT "$<TARGET_PROPERTY:${current_target},BINARY_DIR>/$<CONFIG>/compile_commands.json"
			CONTENT "${cc_json_content}"
			TARGET ${current_target}
			FILE_PERMISSIONS OWNER_EXECUTE OWNER_WRITE OWNER_READ GROUP_READ GROUP_EXECUTE
		)
	endforeach()

	unset(_tmp)
	unset(_tmp2)
	unset(current_target)
	unset(current_source)
	unset(current_config)
endfunction()

function(clang_format)
	list(APPEND CMAKE_MESSAGE_INDENT "[clang-format] ")
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"DEPENDENCY;GLOBAL"
		"REGEX;VERSION"
		"TARGETS"
	)

	find_program(CLANG_FORMAT_BIN
		NAMES
			"clang-format"
		HINTS
			"${CLANG_PATH}"
		PATHS
			/bin
			/sbin
			/usr/bin
			/usr/local/bin
		PATH_SUFFIXES
			bin
			bin64
			bin32
		DOC "Path (or name) of the clang-format binary"
	)
	if(NOT CLANG_FORMAT_BIN)
		message(WARNING "Clang for CMake: Could not find clang-format at path '${CLANG_FORMAT_BIN}', disabling clang-format...")
		list(POP_BACK CMAKE_MESSAGE_INDENT)
		return()
	endif()

	# Validate Version
	if (_ARGS_VERSION)
		set(_VERSION_RESULT "")
		set(_VERSION_OUTPUT "")
		execute_process(
			COMMAND "${CLANG_FORMAT_BIN}" --version
			WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
			RESULT_VARIABLE _VERSION_RESULT
			OUTPUT_VARIABLE _VERSION_OUTPUT
			OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_STRIP_TRAILING_WHITESPACE
			ERROR_QUIET
		)
		if(NOT _VERSION_RESULT EQUAL 0)
			message(WARNING "Clang for CMake: Could not discover version, disabling clang-format...")
			list(POP_BACK CMAKE_MESSAGE_INDENT)
			return()
		endif()
		string(REGEX MATCH "([0-9]+\.[0-9]+\.[0-9]+)" _VERSION_MATCH ${_VERSION_OUTPUT})
		if(NOT ${_VERSION_MATCH} VERSION_GREATER_EQUAL ${_ARGS_VERSION})
			message(WARNING "Clang for CMake: Old version discovered, disabling clang-format...")
			list(POP_BACK CMAKE_MESSAGE_INDENT)
			return()
		endif()
	endif()

	# Default Filter
	if(NOT _ARGS_REGEX)
		set(_ARGS_REGEX "\.(h|hpp|c|cpp)$")
	endif()

	# Go through each target
	foreach(current_target ${_ARGS_TARGETS})
		get_target_property(target_sources_rel ${current_target} SOURCES)
		set(target_sources "")
		foreach(_tmp ${target_sources_rel})
			get_filename_component(_tmp "${_tmp}" ABSOLUTE)
			file(TO_CMAKE_PATH "${_tmp}" _tmp)
			list(APPEND target_sources "${_tmp}")
		endforeach()
		list(FILTER target_sources INCLUDE REGEX "${_ARGS_REGEX}")
		unset(target_sources_rel)

		get_target_property(target_source_dir_rel ${current_target} SOURCE_DIR)
		get_filename_component(target_source_dir ${target_source_dir_rel} ABSOLUTE)
		unset(target_source_dir_rel)

		add_custom_target(${current_target}_clang-format
			COMMAND "${CLANG_FORMAT_BIN}" -style=file -i ${target_sources}
			COMMENT "clang-format: Formatting ${current_target}..."
			WORKING_DIRECTORY "${target_source_dir}"
		)

		# IDE Folder
		get_property(folder TARGET ${current_target} PROPERTY FOLDER)
		set_target_properties(${current_target} PROPERTIES FOLDER "${folder}")

		if(_ARGS_DEPENDENCY)
			add_dependencies(${current_target} ${current_target}_clang-format)
		endif()

		if(_ARGS_GLOBAL)
			if(TARGET clang-format)
				add_dependencies(clang-format ${current_target}_clang-format)
			else()
				add_custom_target(clang-format
					DEPENDS
						${current_target}_clang-format
					COMMENT
						"clang-format: Formatting..."
				)
				set_target_properties(clang-format PROPERTIES
					FOLDER Clang
				)
			endif()
		endif()
	endforeach()
	list(POP_BACK CMAKE_MESSAGE_INDENT)
endfunction()

function(clang_tidy)
list(APPEND CMAKE_MESSAGE_INDENT "[clang-tidy] ")
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"DEPENDENCY;GLOBAL"
		"REGEX;VERSION"
		"TARGETS"
	)

	find_program(CLANG_TIDY_BIN
		NAMES
			"clang-tidy"
		HINTS
			"${CLANG_PATH}"
		PATHS
			/bin
			/sbin
			/usr/bin
			/usr/local/bin
		PATH_SUFFIXES
			bin
			bin64
			bin32
		DOC "Path (or name) of the clang-tidy binary"
	)
	if(NOT CLANG_TIDY_BIN)
		message(WARNING "Clang for CMake: Could not find clang-tidy at path '${CLANG_TIDY_BIN}', disabling clang-tidy...")
		list(POP_BACK CMAKE_MESSAGE_INDENT)
		return()
	endif()

	# Validate Version
	if (_ARGS_VERSION)
		set(_VERSION_RESULT "")
		set(_VERSION_OUTPUT "")
		execute_process(
			COMMAND "${CLANG_TIDY_BIN}" --version
			WORKING_DIRECTORY "${CMAKE_CURRENT_LIST_DIR}"
			RESULT_VARIABLE _VERSION_RESULT
			OUTPUT_VARIABLE _VERSION_OUTPUT
			OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_STRIP_TRAILING_WHITESPACE
			ERROR_QUIET
		)
		if(NOT _VERSION_RESULT EQUAL 0)
			message(WARNING "Clang for CMake: Could not discover version, disabling clang-tidy...")
			list(POP_BACK CMAKE_MESSAGE_INDENT)
			return()
		endif()
		string(REGEX MATCH "([0-9]+\.[0-9]+\.[0-9]+)" _VERSION_MATCH ${_VERSION_OUTPUT})
		if(NOT ${_VERSION_MATCH} VERSION_GREATER_EQUAL ${_ARGS_VERSION})
			message(WARNING "Clang for CMake: Old version discovered, disabling clang-tidy...")
			list(POP_BACK CMAKE_MESSAGE_INDENT)
			return()
		endif()
	endif()

	# Default Filter
	if(NOT _ARGS_REGEX)
		set(_ARGS_REGEX "\.(h|hpp|c|cpp)$")
	endif()

	# Go through each target
	foreach(current_target ${_ARGS_TARGETS})
		# Source Directory
		get_target_property(_tmp2 ${current_target} SOURCE_DIR)
		get_filename_component(target_source_dir ${_tmp2} ABSOLUTE)
		file(TO_CMAKE_PATH "${target_source_dir}" target_source_dir_nat)
		unset(_tmp2)

		# Binary Directory
		get_target_property(_tmp2 ${current_target} BINARY_DIR)
		get_filename_component(target_binary_dir ${_tmp2} ABSOLUTE)
		file(TO_CMAKE_PATH "${target_binary_dir}" target_binary_dir_nat)
		unset(_tmp2)

		# Sources
		get_target_property(_tmp2 ${current_target} SOURCES)
		set(target_sources "")
		foreach(_tmp ${_tmp2})
			get_filename_component(_tmp ${_tmp} ABSOLUTE)
			file(TO_CMAKE_PATH "${_tmp}" _tmp)
			list(APPEND target_sources "${_tmp}")
		endforeach()
		list(FILTER target_sources INCLUDE REGEX "${_ARGS_REGEX}")
		unset(_tmp2)

		add_custom_target(${current_target}_clang-tidy
			COMMENT "clang-tiy: Tidying ${current_target}..."
			WORKING_DIRECTORY "${target_binary_dir}"
			VERBATIM
		)
		foreach(_tmp ${target_sources})
			add_custom_command(
				TARGET ${current_target}_clang-tidy
				POST_BUILD
				COMMAND "${CLANG_TIDY_BIN}"
				ARGS --quiet -p="$<TARGET_PROPERTY:${current_target},BINARY_DIR>/$<CONFIG>" "${_tmp}"
				WORKING_DIRECTORY "${target_binary_dir}"
				COMMAND_EXPAND_LISTS
			)
		endforeach()

		# IDE Folder
		get_property(folder TARGET ${current_target} PROPERTY FOLDER)
		set_target_properties(${current_target} PROPERTIES FOLDER "${folder}")

		if(_ARGS_DEPENDENCY)
			add_dependencies(${current_target} ${current_target}_clang-tidy)
		endif()

		if(_ARGS_GLOBAL)
			if(TARGET clang-tidy)
				add_dependencies(clang-tidy ${current_target}_clang-format)
			else()
				add_custom_target(clang-tidy
					DEPENDS
						${current_target}_clang-tidy
					COMMENT
						"clang-tiy: Tidying..."
				)
				set_target_properties(clang-tidy PROPERTIES
					FOLDER Clang
				)
			endif()
		endif()
	endforeach()
	list(POP_BACK CMAKE_MESSAGE_INDENT)
endfunction()
