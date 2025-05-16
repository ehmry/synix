#! @shell@

systemConfig=@systemConfig@

export HOME=/root PATH="@path@"

# Print a greeting.
echo
echo "[1;32m<[1;97m<[1;90m<[1;31m<[1;97m @distroName@ Stage 2 [1;31m>[1;90m>[1;97m>[1;32m>[0m"
echo

# Normally, stage 1 mounts the root filesystem read/writable.
# However, in some environments, stage 2 is executed directly, and the
# root is read-only.  So make it writable here.
if [ -z "$container" ]; then
    mount -n -o remount,rw none /
fi

if [ ! -c /dev/kmsg ] ; then
    echo "booting system configuration ${systemConfig}"
else
    echo "booting system configuration $systemConfig" > /dev/kmsg
fi

# Make /nix/store a read-only bind mount to enforce immutability of
# the Nix store.  Note that we can't use "chown root:nixbld" here
# because users/groups might not exist yet.
# Silence chown/chmod to fail gracefully on a readonly filesystem
# like squashfs.
chown -f 0:30000 /nix/store
chmod -f 1775 /nix/store
if [ -n "@readOnlyNixStore@" ]; then
    # #375257: Ensure that we pick the "top" (i.e. last) mount so we don't get a false positive for a lower mount.
    if ! [[ "$(findmnt --direction backward --first-only --noheadings --output OPTIONS /nix/store)" =~ (^|,)ro(,|$) ]]; then
        if [ -z "$container" ]; then
            mount --bind /nix/store /nix/store
        else
            mount --rbind /nix/store /nix/store
        fi
        mount -o remount,ro,bind /nix/store
    fi
fi

# Required by the activation script
install -m 0755 -d /etc
if [ ! -h "/etc/nixos" ]; then
    install -m 0755 -d /etc/nixos
fi
install -m 01777 -d /tmp


# Run the script that performs all configuration activation that does
# not have to be done at boot time.
echo "running activation script..."
$systemConfig/activate


# Record the boot configuration.
ln -sfn "$systemConfig" /run/booted-system


# Run any user-specified commands.
@shell@ @postBootCommands@

# This tells Rust programs built with jemallocator to be very aggressive about keeping their
# heaps small. Synit currently targets small machines. Without this, I have seen the system
# syndicate-server take around 300MB of heap when doing not particularly much; with this, it
# takes about 15MB in the same state. There is a performance penalty on being so aggressive
# about heap size, but it's more important to stay small in this circumstance right now. - tonyg
export _RJEM_MALLOC_CONF="narenas:1,tcache:false,dirty_decay_ms:0,muzzy_decay_ms:0"

echo "starting Synit..."
exec @synitPid1Cmd@
