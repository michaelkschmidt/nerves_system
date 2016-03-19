# Nerves
[![Build Status](https://travis-ci.org/nerves-project/nerves-system-br.png?branch=master)](https://travis-ci.org/nerves-project/nerves-system-br)

Build the cross-compiler, various tools, and the base root filesystem
for creating embedded firmware images from Erlang/OTP releases. This
project uses [Buildroot](http://buildroot.net/) to do all of the hard
work. It just provides a configuration and a few helper scripts and
patches to customize Buildroot for Erlang/OTP embedded projects.

Currently, most development is being done on the BeagleBone Black and Raspberry
Pi, but some embedded x86 platforms have starter configs as well. Porting
to other platforms is easy especially if they're already support by Buildroot.
See the `configs` directory for examples.

Discussion or questions? Join us on the \#nerves channel on the [elixir-lang
Slack](https://elixir-slackin.herokuapp.com/).

## First time build

If you're using OSX or Windows, you'll either need to use a pre-built version of
a Nerves system (see the releases tab on GitHub or the [CI build
products](http://nerves-releases.s3.amazonaws.com/list.html)) or create a Linux
VM on your machine.

Only 64-bit Linux systems are supported for building Nerves system images due to
the crosscompilers being used.

Before building a Nerves system image, it is important to have a few build tools
already installed. Buildroot provides a lot, but it does depend on
a few host programs. If using Ubuntu, run the following:

    sudo apt-get install git g++ libssl-dev libncurses5-dev bc m4 make unzip

Nerves downloads a large number of files to build the toolchain, Linux kernel,
Erlang, and other tools. It is recommended that you create a top level directory
to cache these files so that future builds can skip the download step. This step
is optional, so you may skip it:

    mkdir ~/.nerves-cache  # optional

Next, you will need to choose an initial platform and configuration. Change
to the nerves-system-br directory and run `make help` for an up-to-date list of options.
Then run the following:

    make <platform>_defconfig

For example, if you're interested in a basic Raspberry Pi configuration, start
out with the `nerves_rpi_defconfig`.

To build, type:

    make

The first time build takes a long time since it has to download and
build lot of code. For the most part, you will not need to rebuild
Nerves unless you switch platforms or need to add libraries and applications
that cannot be pulled in by `rebar` or `erlang.mk`.

If you'd like to try out the base image on your platform and your platform
supports running code from SDCards, insert an SDCard into your computer (via USB
SDCard reader or otherwise) and run:

    make burn

It should automatically find the SDCard. If it doesn't, you may have to run
`fwup` manually. The `fwup` invocation that it tries is displayed for help.

## Using Nerves

In order to use the cross-compiler and the version of Erlang built by
Buildroot, you'll need to source a shell script to update various
environment settings.

    source ./nerves-env.sh

This step has to be done each time you launch a shell. The key environment settings
updated by the script are the `PATH` variable and a set of variables that direct
build tools such as `rebar`, `mix`, `relx`, and other `Makefiles` to invoke the
cross-compiler.

## Updating Nerves

If it turns out that you need another library or application on
your target that can't be pulled in with `rebar`, you'll need
to update the Buildroot configuration. Luckily, Buildroot comes
with recipes for cross-compiling tons of packages. To change the
configuration, first run the Buildroot configuration utility from
the nerves-system-br directory:

    make menuconfig

You'll probably be interested in the "Package Selection for the target"
menu option. After you're done, run `make` to rebuild Nerves. If you
want to save your set of options permanently, you'll need to copy
`buildroot/defconfig` to the `configs` directory.

Be aware that Buildroot caches the root filesystem between builds
and that when you unselect a configuration option, it will not
disappear from the Nerves root file system image until a clean
build.

The [Buildroot documentation](http://buildroot.net/docs.html) is very helpful if
you're having trouble.

## Built-in Configurations

Nerves comes with several configurations out of the box. These can be
used directly or just as an examples for your own custom configuration.
Some old configurations of interest may also be in the `configs/unsupported`
directory. Nerves configurations have the form
`nerves_<target>_<language>_defconfig`. Languages include Erlang, Elixir, and
LFE. The language really only specifies the prompt that gets shown on boot, so
do not be discouraged if a default configuration doesn't exist for your desired
language (Run `make nerves_xxx_defconfig` where `xxx` is the closest config for
your target, then run `make menuconfig` and go to `User-provided
options->nerves-config`.)

Ignoring the language options, the following defconfigs are supported:

### nerves_bbb_<language>_defconfig

This is the default configuration for building images for the Beaglebone
Black. It is a minimal image intended for applications that do not require
a lot of hardware or C library support.

To use USB on the Beaglebone Black, you will need to run `os:cmd("modprobe musb_dsps").`
as part of your Erlang program's initialization.

### nerves_rpi_<language>_defconfig

This is an initial configuration for building images for the Raspberry Pi.
It is a minimal image similar to the one built for the Beaglebone Black.

A shell is run on the attached HDMI monitor and USB keyboard. If you would like to
use the shell on the UART pins on the GPIO hearer, the terminal should
be changed to `ttyAMA0`. To change, run the following:

    make nerves_rpi_<language>_defconfig
    make menuconfig
    # Go to "User-provided options" -> nerves-config-> console port
    # Press enter to select, and change to ttyAMA0
    # Exit the menuconfig
    cp buildroot/defconfig configs/my_rpi_defconfig
    make

### nerves_rpi2_<language>_defconfig

If you have a Raspberry Pi 2, start with this defconfig. It is similar to
`nerves_rpi_defconfig` except that it enables support for the quad core
processor in the Pi 2. A multi-core version of the Erlang VM will also be built.

### bbb_linux_defconfig

This configuration produces a Linux image. It is not useful for Erlang
development, but it can be helpful when getting unfamiliar hardware to work.
I use it to debug Linux kernel issues since most documentation and
developers expect a traditional shell-based environment.
