#!/bin/sh
# the next line restarts using -*-Tcl-*-sh \
exec /usr/bin/tclsh "$0" ${1+"$@"}

if { [info exists env(OCTOPUS_INSTALL_PATH) ] } {
        lappend auto_path $env(OCTOPUS_INSTALL_PATH)
} else {
        puts "ERROR: Please set environmental variable OCTOPUS_INSTALL_PATH to point to the location of octopus.tcl file"
        exit 1
}

package require octopus 0.1
package require octopusNC 0.1
namespace import ::octopus::*
namespace import ::octopusNC::*

################################################################################
# BEGIN check_set_flo

proc check_set_flo {x} {
	upvar f f
	upvar l l 
	upvar o o 
	upvar warning_given warning_given
	if { [ llength $x ] == 4 } {
		if { ! [info exists warning_given] } {
			display_message info "List item detected for $x."
			display_message none    " <Type> might disappear in the future since irun/octopus/etc. should be able to detect it automatically"
			set warning_given "true"
		}
		set f [lindex $x 0]
		set t [lindex $x 1]
		set l [lindex $x 2]
		set o [lindex $x 3]
		if { ! [string match "* $t *" " vhdl verilog vlog verilogams vams " ] } {
			display_message error "unrecognised type $t for file $f"
			display_message error "Type can be either vhdl/verilog/vlog/verilogams/vams"
		}
	} elseif { [ llength $x ] == 3 } {
		set f [lindex $x 0]
		set l [lindex $x 1]
		set o [lindex $x 2]
	} else {
		display_message error "Wrong format detected. List content is: $x while it should be <file> \[<type>\] <library> <options>"
		set f "<ERROR in source file>"
		set l "<ERROR in source file>"
		set o "<ERROR in source file>"
	}
	::octopus::append_cascading_variables
}

# END check_set_flo
################################################################################

################################################################################
# BEGIN Generating ${cds-lib} if necessary
proc generate_cds_lib args {

	set var_array(10,file)    		[list "--file" "<none>" "string" "1" "1" "" "Input file from which cds.lib is generated"]
	set var_array(20,generate-cds-file)  	[list "--generate-cds-file" "" "string" "1" "1" "" "Name of the output \"cds.lib\" file."]

	::octopus::extract_check_options_data

	::octopus::abort_on error --return

	# This variables contains all lists with RTL/type/library/other options
	set file_set_total [::octopus::parse_file_set --type utel --file $file]

	display_message info "Generating ${generate-cds-file}"
	exec rm -rf ${generate-cds-file}

	set fileId_cdslib [open ${generate-cds-file} {WRONLY CREAT} 0740]
	set libraries ""
	foreach x $file_set_total {
		check_set_flo $x
		################################################################################
		# BEGIN detection of a duplicated library in the file_set_total
		if { [lsearch $libraries $l ] == -1 } {
			# Create the directory for the library
			exec mkdir -p [file dirname ${generate-cds-file}]/$l
			# Add the library in the list so we do not have double entries in the ${generate-cds-file}
			lappend libraries $l
			# Add the library in the $cdslib
			puts $fileId_cdslib "DEFINE $l $l"
		}
		# END
		################################################################################
	}
	close $fileId_cdslib
	puts ""
	display_message info "DONE: Generating ${generate-cds-file}"
}
# END
################################################################################


################################################################################
# BEGIN Generating a single output file
proc generate_fileset args {

	upvar #0 env env

	set var_array(10,file)    	[list "--file" "<none>" "string" "1" "1" "" "Input file from which cds.lib is generated"]
	set var_array(10,output-file)  	[list "--output-file" "<none>" "string" "1" "1" "" "Name of the output file."]

	::octopus::extract_check_options_data

	::octopus::abort_on error --return

	set help_head {
		display_message none "Generates a single list file with duplicates entries removed."
	}
	set file_set_total [::octopus::parse_file_set --type utel --file $file]

	set fileId_filesetout [open ${output-file} w 0740]
	puts $fileId_filesetout "# Derived from: ${file}"
	puts $fileId_filesetout "# Generated by: [uplevel {file tail $argv0} ]"
	puts $fileId_filesetout "#           on: [exec date]"
	puts $fileId_filesetout "set file_set \{"

	################################################################################
	# BEGIN parsing the fileset file
	set files ""
	set equivalent_files "" ; # equivalent files are those that can be compiled together
	foreach x $file_set_total {
		check_set_flo $x
		if { [lsearch $files [subst $f] ] == -1 } {
			# Add the file in the list so we do not have double entries
			lappend files [subst $f]
			puts $fileId_filesetout "\{ \{$f\} \{$l\} \{$o\}  \}"
		} else {
			# duplicate file
			display_message info "Duplicate file ($f)"
			continue
		}
	}
	puts ""
	puts $fileId_filesetout "\}"
	close $fileId_filesetout
}
# END
################################################################################


################################################################################
# BEGIN procedure for parsing the fileset file(s)
proc irun_fileset args {

	upvar #0 env env

	set var_array(10,file)    	[list "--file" "<none>" "string" "1" "infinity" "" "Input file contains all files to be compiled"]
	set var_array(20,template)	[list "--template" "" "string" "1" "1" "" "Specify the name of the template script to write out"]
	set var_array(30,irun-option)	[list "--irun-option" "" "string" "1" "1" "" "If user wants to pass additional command line options to irun command"]

	::octopus::extract_check_options_data

	::octopus::abort_on error --return


	exec mkdir -p log; catch {eval exec rm -rf [glob log/*log]}

	set file_set_total [::octopus::parse_file_set --type utel --file $file]

	set irun "$env(CADENV_HOME)/cadbin/irun -64 ${irun-option}"

	# Do the executables exist?
	::octopus::check_file --type exe --file $env(CADENV_HOME)/cadbin/irun

	::octopus::abort_on error

	if { "$template" != "" } {
		set fileId_template [open $template {WRONLY APPEND CREAT} 0740 ]
	}

	set irun_files ""
	set previous_lib ""
	set previous_opt ""
	foreach x $file_set_total {
		check_set_flo $x
		display_message debug "<2> $f"
		if { "$previous_lib" != "$l" || "$previous_opt" != "$o"  } {
			if { "$irun_files" == "" } {
				set irun_files "$irun_files \\\n-makelib $l"
			} else {
				set irun_files "$irun_files \\\n${accumulate_file} \\\n-endlib \\\n-makelib $l \\\n${o}"
			}
			set previous_lib $l
			set previous_opt $o
			set accumulate_file "  $f"
		} else {
			set accumulate_file "$accumulate_file \\\n  $f"
		}
	}
	set irun_files "$irun_files \\\n${o} \\\n${accumulate_file} \\\n-endlib"

	# END
	set cmd [concat $irun $irun_files \\\n-l "log/irun.log"]
	if { "$template" != "" } {
		# Replace $env(VARIABLE) with $VARIABLE
		regsub -all {env\(([^\s]+)\)} $cmd {\1} cmd_template
		puts $fileId_template "$cmd_template"
	}
	display_message info "Invoking irun... Be patient."
	if { [catch {eval exec $cmd >&@stdout}] } {
		display_message error "Running irun. Check log/irun.log for additional information."
	}

	::octopus::append_cascading_variables
	puts ""
	display_message info "DONE: Running irun"
}
# END procedure for parsing the fileset file(s)
################################################################################


################################################################################
# BEGIN command line argument parsing
regexp {(.*/data/)([^/]+_lib)/([^/]+)/.*} [exec pwd] EXEC_PATH DATA_PATH CRT_LIB CRT_CELL

set var_array(10,file)			[list "--file" "<none>" "string" "1" "infinity" "" "TCL source fileset(s) list. More than one can be specified. a RTL Compiler script using read_hdl procedure can also be loaded."]
set var_array(20,fileset-out)		[list "--fileset-out" "" "string" "1" "1" "" "Writes out a new fileset removing duplicate entries"]
set var_array(30,generate-cds-lib)	[list "--generate-cds-lib" "" "string" "1" "1" "" "Generates a cds.lib file automatically. For irun this is not recommended."]
set var_array(60,no-irun)		[list "--no-irun" "false" "boolean" "1" "1" "" "Prevents running irun."]
set var_array(70,irun-option)		[list "--irun-option" "-v93 -top $CRT_CELL" "string" "1" "1" "" "If user wants to pass additional command line options to irun command. "]
set var_array(80,template)		[list "--template" "" "string" "1" "1" "" "Specify the name of the standalone template script."]

set help_head {
	puts "[uplevel {file tail $argv0} ]"
	puts ""
	puts "Description:"
	puts "  Starts irun on the file sets."
	puts "  This utility can also:"
	puts "    - generate cds.lib file"
	puts "    - bash shell script for standalone run"
	puts ""
}

set help_tail {
	puts "Note:"
	puts "  When specifying --irun-option make sure you also include -top option or you'll get the following error:  "
	puts "  *E,NODSN: There are no design files being compiled."
	puts ""
}

::octopus::extract_check_options_data

::octopus::abort_on error --display-help

################################################################################

################################################################################
# BEGIN Verify that the $fileset-out/$cds-lib files are not existent in case they are specified
set arguments "fileset-out generate-cds-lib"
foreach crt_arg $arguments {
	if {   "[set $crt_arg ]" != "" && [ file exists [set $crt_arg] ] && ! [file writable [set $crt_arg]] } {
		display_message error "File [set $crt_arg] is not writable."
	}
}

::octopus::abort_on error --display-help

# END Verify that the $fileset-out/$cds-lib files are not existent
################################################################################

if { "$template" != "" } {
	exec rm -rf $template
	set fileId_template [open $template {WRONLY CREAT} 0740]
	puts $fileId_template "#!/bin/bash"
	puts $fileId_template "#Generated by: $argv0 $argv"
	puts $fileId_template "#Generation date: [exec date]"
	puts $fileId_template ""
	puts $fileId_template "# exit at any error"
	puts $fileId_template "set -e"
	puts $fileId_template ""
	close $fileId_template
}

################################################################################
# BEGIN parse file-set including compilation/cds.lib creation/removing duplicate files/etc.
# Collect all the source files specified on the command line
::octopus::check_file --type tcl --file ${file}
::octopus::abort_on error

if { "${generate-cds-lib}" != "" } {
	generate_cds_lib --file ${file} --generate-cds-file ${generate-cds-lib}
}

if { "${fileset-out}" != "" } {
	generate_fileset --file ${file} --output-file ${fileset-out}
}

if { "${no-irun}" == "false" } {
	irun_fileset --file ${file} --template $template --irun-option ${irun-option}
	display_strange_warnings_fatals --file "log/irun.log"
}
::octopus::abort_on error --messages
# END
################################################################################
