#!/usr/bin/env -S tclsh

# TODO: periodic cleanup.

package require syndicate
namespace import preserves::*

# Initial permissions for creating files.
set safePerm 0600

# Write some content to a file
proc writeContent {chan content} {
  if {$content != ""} {
    puts $chan $content
  }
}


# Set file attributes in the calling scope.
proc setAttrs {} {
  uplevel 1 {
    set cmd [list file attributes $path -permissions "0$perm"]
    foreach u [project -unpreserve $user {string}] {
      lappend cmd -owner $u
    }
    foreach g [project -unpreserve $group {string}] {
      lappend cmd -group $g
    }
    {*}$cmd
  }
}

syndicate::spawn actor {
  set tmpfilesEntity [createAssertHandler {value handle} {
    preserves::project $value {^ tmpfiles-dataspace / } ds
    if {$ds == ""} {
      puts stderr "unrecognized assertion $value
      return
    }
    proc dataspace {} [list return $ds]

    during {@rule #(<tmpfile @type #? @path #? @perm #? @user #? @group #? @age #? @arg #?>)} {
      project -unpreserve $path {string} path
      project -unpreserve $arg  {string} arg
      if {$path == ""} return
      if {$perm == {#f}} {
        if {$type == "d" || $type == "D" || $type == "e"} {
          set perm 0755
        } else {
          set perm 0644
        }
      }
      if {[catch {
        switch $type {

          f {
            if {![file exists $path]} {
              set f [open $path w] $safePerm
              writeContent $f $arg
              close $f
              setAttrs
            }
          }

          f+ {
            set f [open $path w] $safePerm
            writeContent $f $arg
            close $f
            setAttrs
          }

          w {
            if {[file exists $path]} {
              set f [open $path w] $safePerm
              writeContent $f $arg
              close $f
              setAttrs
            }
          }

          w+ {
            if {[file exists $path]} {
              set f [open $path a] $safePerm
              writeContent $f $arg
              close $f
              setAttrs
            }
          }

          d {
            file mkdir $path
            setAttrs
          }

          D {
            file mkdir $path
            setAttrs
          }

          L {
            if {$arg != ""} {
              if {![file exists $path]} {
                file link -symbolic $path $arg
              }
            }
          }

          L+ {
            if {$arg != ""} {
              if {[file exists $path]} {
                file delete -force -- $path
              }
              file link -symbolic $path $arg
            }
          }
          
          L? {
            if {$arg != "" && [file exists $arg]} {
              file link -symbolic $path $arg
            }
          }

          r {
            if {[file exists $path]} {
              file delete -force $path
            }
          }

          R {
            if {[file isDirectory $path]} {
              file delete -force $path
            }
          }

        }
      } err]} {
        puts stderr "failed to execute rule $rule: $err"

        # Assert an error back into the tmpfiles dataspace.
        assert "<error \"$err\" $rule>" [dataspace]
      }
    } [dataspace]
    
  }]

  connectStdio $tmpfilesEntity
}

vwait forever
