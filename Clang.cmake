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
			get_target_include_directories(INTERFACE OUTPUT cc_src_command TARGET "${_tmp}" IGNORE ${ignore})
			foreach(_tmp3 ${cc_src_command})
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
			get_target_definitions(INTERFACE OUTPUT cc_src_command TARGET "${_tmp}" IGNORE ${ignore})
			foreach(_tmp3 ${cc_src_command})
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

macro(cstd_to_flag output version default)
	set(${output} "${default}")
	if(MSVC)
		if("${version}" GREATER_EQUAL 17)
			set(${output} "/std:c17")
		elseif("${version}" GREATER_EQUAL 11)
			set(${output} "/std:c11")
		endif()
	else()
		if("${version}" GREATER_EQUAL 23)
			set(${output} "-std=c2x")
		elseif("${version}" GREATER_EQUAL 17)
			set(${output} "-std=c17")
		elseif("${version}" GREATER_EQUAL 11)
			set(${output} "-std=c11")
		elseif("${version}" GREATER_EQUAL 99)
			set(${output} "-std=c99")
		elseif("${version}" GREATER_EQUAL 90)
			set(${output} "-std=c90")
		endif()
	endif()
endmacro()

macro(cxxstd_to_flag output version default)
	set(${output} "${default}")
	if(MSVC)
		if("${version}" GREATER_EQUAL 23)
			set(${output} "/std:c++latest")
		elseif("${version}" GREATER_EQUAL 20)
			set(${output} "/std:c++20")
		elseif("${version}" GREATER_EQUAL 17)
			set(${output} "/std:c++17")
		elseif("${version}" GREATER_EQUAL 14)
			set(${output} "/std:c++14")
		endif()
	else()
		if("${version}" GREATER_EQUAL 23)
			set(${output} "-std=c++23")
		elseif("${version}" GREATER_EQUAL 20)
			set(${output} "-std=c++20")
		elseif("${version}" GREATER_EQUAL 17)
			set(${output} "-std=c++17")
		elseif("${version}" GREATER_EQUAL 14)
			set(${output} "-std=c++14")
		elseif("${version}" GREATER_EQUAL 11)
			set(${output} "-std=c++11")
		elseif("${version}" GREATER_EQUAL 98)
			set(${output} "-std=c++98")
		endif()
	endif()
endmacro()

function(generate_compile_commands_json)
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		""
		"REGEX"
		"TARGETS"
	)
	if(NOT _ARGS_REGEX)
		set(_ARGS_REGEX "\\.(h|c)(|pp)$")
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
		foreach(current_target ${_ARGS_TARGETS})
			set_target_properties(${current_target} PROPERTIES
				CMAKE_EXPORT_COMPILE_COMMANDS ON
			)
		endforeach()
		return()
	endif()

	if(MSVC)
		set(_define_prefix "/D")
		set(_include_prefix "/I")
	else()
		set(_define_prefix "-D")
		set(_include_prefix "-I")
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
		cxxstd_to_flag(cc_tgt_std_CXX "${cc_tgt_std_CXX}" "")

		# C standard
		get_property(cc_tgt_std_C TARGET ${current_target} PROPERTY C_STANDARD)
		cstd_to_flag(cc_tgt_std_C "${cc_tgt_std_C}" "")

		# Include Directories
		get_property(_tmp TARGET ${current_target} PROPERTY INCLUDE_DIRECTORIES)
		foreach(cc_src_command ${_tmp})
			cmake_path(ABSOLUTE_PATH cc_src_command BASE_DIRECTORY "${cc_tgt_source_dir}")
			list(APPEND cc_tgt_includes "${cc_src_command}")
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
				foreach(cc_src_command ${_tmp})
					cmake_path(ABSOLUTE_PATH cc_src_command BASE_DIRECTORY "${cc_tgt_source_dir}")
					list(APPEND cc_tgt_includes "${cc_src_command}")
				endforeach()
				get_property(_tmp TARGET ${_tmp3} PROPERTY INTERFACE_SYSTEM_INCLUDE_DIRECTORIES)
				foreach(cc_src_command ${_tmp})
					cmake_path(ABSOLUTE_PATH cc_src_command BASE_DIRECTORY "${cc_tgt_source_dir}")
					list(APPEND cc_tgt_includes "${cc_src_command}")
				endforeach()

				# - Interface Defines, Options
				get_property(_tmp TARGET ${current_target} PROPERTY INTERFACE_COMPILE_DEFINITIONS)
				foreach(cc_src_command ${_tmp})
					list(APPEND cc_tgt_definitions "${cc_src_command}")
				endforeach()
				get_property(_tmp TARGET ${current_target} PROPERTY INTERFACE_COMPILE_OPTIONS)
				foreach(cc_src_command ${_tmp})
					list(APPEND cc_tgt_options "${cc_src_command}")
				endforeach()
			endif()
		endforeach()

		# Figure out source files for this target.
		set(cc_tgt_sources "")
		get_target_property(cc_tgt_sources_raw ${current_target} SOURCES)
		foreach(cc_tgt_source ${cc_tgt_sources_raw})
			cmake_path(ABSOLUTE_PATH cc_tgt_source BASE_DIRECTORY "${cc_tgt_source_dir}")
			list(APPEND cc_tgt_sources "${cc_tgt_source}")
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

			if(cc_src_language STREQUAL "CXX")
				# C++ Standard
				get_property(cc_src_std_CXX SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY CXX_STANDARD)
				cxxstd_to_flag(cc_src_std "${cc_src_std_CXX}" "${cc_tgt_std_CXX}")
			else()
				# C standard
				get_property(cc_src_std_C SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY C_STANDARD)
				cstd_to_flag(cc_src_std "${cc_src_std_C}" "${cc_tgt_std_C}")
			endif()

			# Compile Options
			set(cc_src_options "${cc_tgt_options}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY COMPILE_OPTIONS)
			foreach(cc_src_command ${_tmp})
				list(APPEND cc_src_options "${cc_src_command}")
			endforeach()

			# Includes
			set(cc_src_includex "${cc_tgt_includes}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY INCLUDE_DIRECTORIES)
			foreach(cc_src_command ${_tmp})
				cmake_path(ABSOLUTE_PATH cc_src_command BASE_DIRECTORY "${cc_tgt_source_dir}")
				list(APPEND cc_src_includex "${cc_src_command}")
			endforeach()

			# Defines
			set(cc_src_defines "${cc_tgt_defines}")
			get_property(_tmp SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY COMPILE_DEFINITIONS)
			foreach(cc_src_command ${_tmp})
				list(APPEND cc_src_defines "${cc_src_command}")
			endforeach()

			#get_property(_ SOURCE ${current_source} TARGET_DIRECTORY ${current_target} PROPERTY _)

			# Generate JSON content.
			set(cc_json_content_entry "{}")

			# Working Directory
			file(TO_CMAKE_PATH "${cc_tgt_source_dir}" _tmp)
			json_escape_string(OUTPUT _tmp INPUT "${_tmp}")
			string(JSON cc_json_content_entry SET ${cc_json_content_entry} "directory" \"${_tmp}\")

			# Target File
			file(TO_CMAKE_PATH "${cc_src_location}" _tmp)
			json_escape_string(OUTPUT _tmp INPUT "${_tmp}")
			string(JSON cc_json_content_entry SET ${cc_json_content_entry} "file" \"${_tmp}\")

			if(ON) # Command
				set(cc_src_command "")

				# cl/cc difference
				if(MSVC)
					list(APPEND cc_src_command "cl")
				else()
					list(APPEND cc_src_command "cc")
				endif()

				# C/CXX Standard
				if(NOT "${cc_src_std}" STREQUAL "")
					list(APPEND cc_src_command "${cc_src_std}")
				endif()

				# Global Flags
				if(MSVC)
					separate_arguments(cc_src_flags WINDOWS_COMMAND ${CMAKE_${cc_src_language}_FLAGS})
				else()
					separate_arguments(cc_src_flags UNIX_COMMAND ${CMAKE_${cc_src_language}_FLAGS})
				endif()
				foreach(flag ${cc_src_flags})
					if(NOT "${flag}" STREQUAL "")
						list(APPEND cc_src_command "${flag}")
					endif()
				endforeach()
				set(cc_src_command_config "")
				foreach(current_config ${cc_configurations})
					string(TOUPPER "${current_config}" current_config_upper)
					list(APPEND cc_src_command_config "$<$<CONFIG:${current_config}>:${CMAKE_${cc_src_language}_FLAGS_${current_config_upper}}>")
				endforeach()
				list(JOIN cc_src_command_config "" cc_src_command_config)
				list(APPEND cc_src_command "${cc_src_command_config}")

				# Definitions
				foreach(define ${cc_src_defines})
					if(NOT "${define}" STREQUAL "")
						list(APPEND cc_src_command "${_define_prefix}${define}")
					endif()
				endforeach()

				# Other Options
				foreach(option ${cc_src_options})
					if(NOT "${option}" STREQUAL "")
						list(APPEND cc_src_command "${option}")
					endif()
				endforeach()

				# Include Directories
				foreach(include ${cc_src_includex})
					if(NOT "${include}" STREQUAL "")
						file(TO_CMAKE_PATH "${include}" _tmp)
						list(APPEND cc_src_command "${_include_prefix}${include}")
					endif()
				endforeach()

				# File to compile
				json_escape_string(OUTPUT cc_src_location INPUT "${cc_src_location}")
				if(MSVC)
					list(APPEND cc_src_command "\"${cc_src_location}\"")
				else()
					list(APPEND cc_src_command "-c \"${cc_src_location}\"")
				endif()

				# Build actual command entry.
				list(JOIN cc_src_command " " cc_src_command)
				json_escape_string(OUTPUT _tmp INPUT "${cc_src_command}")
				string(JSON cc_json_content_entry SET ${cc_json_content_entry} "command" \"${_tmp}\")
			endif()

			string(APPEND cc_json_content "${cc_json_content_entry},\n")
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
	unset(cc_src_command)
	unset(current_target)
	unset(current_source)
	unset(current_config)
endfunction()

function(clang_format)
	list(APPEND CMAKE_MESSAGE_INDENT "[clang-format] ")
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"DEPENDENCY"
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
		set(_ARGS_REGEX "\\.(h|hpp|c|cpp)$")
	endif()

	# Go through each target
	foreach(current_target ${_ARGS_TARGETS})
		set(designed_target "${current_target}_clang-format")

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

		add_custom_target(${designed_target}
			COMMAND "${CLANG_FORMAT_BIN}" -style=file -i ${target_sources}
			COMMENT "clang-format: Formatting ${current_target}..."
			WORKING_DIRECTORY "${target_source_dir}"
		)

		# IDE Folder & Label
		get_target_property(folder ${current_target} FOLDER)
		get_target_property(label ${current_target} PROJECT_LABEL)
		if(folder)
			set_target_properties(${designed_target} PROPERTIES FOLDER ${folder})
		else()
			set_target_properties(${designed_target} PROPERTIES FOLDER Clang)
		endif()
		if(label)
			set_target_properties(${designed_target} PROPERTIES PROJECT_LABEL "${label} (clang-format)")
		else()
			set_target_properties(${designed_target} PROPERTIES PROJECT_LABEL "${current_target} (clang-format)")
		endif()

		if(_ARGS_DEPENDENCY)
			add_dependencies(${current_target} ${designed_target})
		endif()

		if(NOT TARGET clang-format)
			add_custom_target(clang-format
				DEPENDS
					${designed_target}
				COMMENT
					"clang-format: Formatting..."
			)
			set_target_properties(clang-format PROPERTIES
				FOLDER Clang
			)
		endif()
		add_dependencies(clang-format ${designed_target})
	endforeach()
	list(POP_BACK CMAKE_MESSAGE_INDENT)
endfunction()

function(clang_tidy)
	list(APPEND CMAKE_MESSAGE_INDENT "[clang-tidy] ")
	cmake_parse_arguments(
		PARSE_ARGV 0
		_ARGS
		"DEPENDENCY"
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
		set(_ARGS_REGEX "\\.(h|hpp|c|cpp)$")
	endif()

	# Go through each target
	foreach(current_target ${_ARGS_TARGETS})
		set(designed_target "${current_target}_clang-tidy")

		# Source Directory
		get_target_property(cc_src_command ${current_target} SOURCE_DIR)
		get_filename_component(target_source_dir ${cc_src_command} ABSOLUTE)
		file(TO_CMAKE_PATH "${target_source_dir}" target_source_dir_nat)
		unset(cc_src_command)

		# Binary Directory
		get_target_property(cc_src_command ${current_target} BINARY_DIR)
		get_filename_component(target_binary_dir ${cc_src_command} ABSOLUTE)
		file(TO_CMAKE_PATH "${target_binary_dir}" target_binary_dir_nat)
		unset(cc_src_command)

		# Sources
		get_target_property(cc_src_command ${current_target} SOURCES)
		set(target_sources "")
		foreach(_tmp ${cc_src_command})
			get_filename_component(_tmp ${_tmp} ABSOLUTE)
			file(TO_CMAKE_PATH "${_tmp}" _tmp)
			list(APPEND target_sources "${_tmp}")
		endforeach()
		list(FILTER target_sources INCLUDE REGEX "${_ARGS_REGEX}")
		unset(cc_src_command)

		add_custom_target(${designed_target}
			COMMENT "clang-tidy: Tidying ${current_target}..."
			WORKING_DIRECTORY "${target_binary_dir}"
			VERBATIM
		)
		foreach(_tmp ${target_sources})
			add_custom_command(
				TARGET ${designed_target}
				POST_BUILD
				COMMAND "${CLANG_TIDY_BIN}"
				ARGS --quiet -p="$<TARGET_PROPERTY:${current_target},BINARY_DIR>/$<CONFIG>" "${_tmp}"
				WORKING_DIRECTORY "${target_binary_dir}"
				COMMAND_EXPAND_LISTS
			)
		endforeach()

		# IDE Folder & Label
		get_target_property(folder ${current_target} FOLDER)
		get_target_property(label ${current_target} PROJECT_LABEL)
		if(folder)
			set_target_properties(${designed_target} PROPERTIES FOLDER ${folder})
		else()
			set_target_properties(${designed_target} PROPERTIES FOLDER Clang)
		endif()
		if(label)
			set_target_properties(${designed_target} PROPERTIES PROJECT_LABEL "${label} (clang-tidy)")
		else()
			set_target_properties(${designed_target} PROPERTIES PROJECT_LABEL "${current_target} (clang-tidy)")
		endif()

		if(_ARGS_DEPENDENCY)
			add_dependencies(${current_target} ${designed_target})
		endif()

		if(NOT TARGET clang-tidy)
			add_custom_target(clang-tidy
				DEPENDS
					${designed_target}
				COMMENT
					"clang-tiy: Tidying..."
			)
			set_target_properties(clang-tidy PROPERTIES
				FOLDER Clang
			)
		endif()
		add_dependencies(clang-tidy ${designed_target})
	endforeach()
	list(POP_BACK CMAKE_MESSAGE_INDENT)
endfunction()
