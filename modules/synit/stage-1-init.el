#!@execlineb@ -P
export PATH @initramfsPath@
export LD_LIBRARY_PATH @extraUtils@/lib
background { s6-echo "\n[1;32m<[1;97m<[1;90m<[1;31m<[1;97m @distroName@ Stage 1 [1;31m>[1;90m>[1;97m>[1;32m>[0m\n" }
export SHELL @shell@

@specialMounts@

# Handle the kernel parameters.
if {
  redirfd -r 0 /proc/cmdline
  forstdin -E -d " " arg case -N $arg {
    init=(.*) {
      importas init 1
      s6-ln -s "${init}" /run/init
    }
    boot.debug1 { # stop right away
      @failScript@
    }
  }
  exit
}

@setHostId@

@preDeviceCommands@

if {
  redirfd -w 1 /proc/sys/kernel/modprobe
  s6-echo @extraUtils@/bin/modprobe
}

background { s6-echo Loading modules @kernelModules@ }
if { modprobe -a @kernelModules@ }

# Start mdevd to load modules and create disk symlinks.
if { s6-mkdir -p /dev/disk/by-label /dev/disk/by-uuid /dev/disk/by-id }
background { mdevd -v 3 -O 2 -f @mdevdConf@ }
importas -iu mdevd_pid !
# Do a blocking coldplug and wait.
foreground { mdevd-coldplug -v 3 -O 2 }
foreground { sleep 1 }

@postDeviceCommands@

# Stop after loading modules and creating device nodes.
if {
  redirfd -r 0 /proc/cmdline
  forstdin -E -d " " arg case -N $arg {
    boot.debug1devices {
      @failScript@
    }
  }
  exit
}

@postResumeCommands@

foreground { s6-echo starting normal mount script }
@normalMounts@

# stop after mounting file systems
if {
  redirfd -r 0 /proc/cmdline
  forstdin -E -d " " arg case -N $arg {
    boot.debug1mounts {
      @failScript@
    }
  }
  exit
}

if {
  forx -pE dir { proc dev sys run }
    mkdir -m 0755 -p /mnt-root/$dir
}

# Wait for children to exit.
background { s6-echo "waiting for children to exit" }
background { kill $mdevd_pid }
wait { }

# Wipe the current root and exec in /mnt-root.
switch_root /mnt-root /run/init
