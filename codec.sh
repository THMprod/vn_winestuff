#!/bin/bash

echo
echo "Helper script to install codecs for VNs on wine (v2023-04-20)"
echo

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

Quit() { echo; exit; }
Heading() { echo; echo "[INSTALL] $@"; }

CheckEnv()
{
    # check for wine. it can be defined in $WINE or found in $PATH
    if [ "$WINE" = "" ]; then WINE="wine"; fi

    if ! command -v "$WINE" >/dev/null; then
        echo "There is no usable wine executable in your PATH."
        echo "Either set it or the WINE variable and try again."
        Quit
    fi

    # check if WINEPREFIX is defined
    if [ "$WINEPREFIX" = "" ]; then
        WINEPREFIX="~/.wine"
        echo "WINEPREFIX is not set. Going to use $WINEPREFIX"
    else
        echo "WINEPREFIX is $WINEPREFIX"
    fi

    # determine arch if it's not defined yet
    if [ "$WINEARCH" = "" ]; then
        if [ ! -d "$WINEPREFIX/drive_c/windows/system32" ]; then
            echo "A wine prefix does not appear to exist yet."
            echo "Please run  wineboot -i  to initialize it."
            Quit
        elif [ -d "$WINEPREFIX/drive_c/windows/syswow64" ]; then
            ARCH="win64"
        else
            ARCH="win32"
        fi
        echo "WINEARCH seems to be $ARCH"
    else
        ARCH=$WINEARCH
        echo "WINEARCH specified as $ARCH"
    fi

    # check for valid WINEARCH  (also end current wine session)
    WINEDEBUG="-all" WINEARCH=$ARCH $WINE wineboot -e || Quit
}

RUN()
{
    echo "[run] $WINE $@"
    WINEDEBUG="-all" $WINE $@

    if [ $? -ne 0 ]; then echo "some kind of error occurred."; Quit; fi
}

GetWindowsVer()
{
    OSVER=$(WINEDEBUG="-all" $WINE winecfg -v | tr -d '\r')
    #echo "OS Ver is $OSVER"
}

SetWindowsVer()
{
    REQVER=$1

    # WinXP 64-bit has its own identifier
    if [[ $REQVER = "winxp" && $ARCH = "win64" ]]; then REQVER="winxp64"; fi

    RUN winecfg -v $REQVER
    GetWindowsVer
}

OverrideDll()
{
    if [ "$2" != "" ]; then DATA="/d $2"; else DATA=""; fi
    RUN reg add "HKCU\\Software\\Wine\\DllOverrides" /f /t REG_SZ /v $1 $DATA
}

SetClassDll32()
{
    if [ $ARCH = "win64" ]; then WOWNODE="\\Wow6432Node"; else WOWNODE=""; fi
    REGKEY="HKLM\\Software${WOWNODE}\\Classes\\CLSID\\{$1}\\InprocServer32"
    RUN reg add $REGKEY /f /t REG_SZ /ve /d $2
}

Hash_SHA256()
{
    HASH=$(sha256sum "$1" | sed -e "s/ .*//" | tr -d '\n')
    if [ $HASH != $2 ]; then
        echo "... hash mismatch on $1"
        echo "download hash $HASH"
        echo "expected hash $2"
        Quit
    fi
}

DownloadFile()
{ # args: $1=output_subdir $2=output_name $3=url $4=hash
    DLFILE=$SCRIPT_DIR/$1/$2
    DLFILEWIP=${DLFILE}.download

    # download installer if we don't have it yet
    WGET_ARGS="--progress=bar"
    if [ ! -f "$DLFILE" ]; then
        # allow resuming if an incomplete file is found
        if [ -f "$DLFILEWIP" ]; then WGET_ARGS="$WGET_ARGS -c"; fi

        # download
        mkdir -p "$SCRIPT_DIR/$1"
        wget $WGET_ARGS -P "$SCRIPT_DIR/$1" -O "$DLFILEWIP" $3

        # delete download if wget failed
        if [[ $? -ne 0 ]]; then
            echo "wget error occurred while downloading $2"
            rm $DLFILEWIP 2> /dev/null
            Quit
        fi

        mv "$DLFILEWIP" "$DLFILE"
    fi

    # file hash must match, otherwise quit
    if [ -f "$DLFILE" ]; then
        Hash_SHA256 "$DLFILE" $4
    else
        echo "$1 is not found, cannot continue."
    fi
}

DownloadFileInternal()
{
    BASEURL="https://raw.githubusercontent.com/b-fission/vn_winestuff/master"
    DownloadFile $1 $2 $BASEURL/$1/$2 $3
}

# ============================================================================

Install_mf()
{
    Heading "mf"

    WORKDIR=$SCRIPT_DIR/mf
    if [ $ARCH = "win64" ]; then SYSDIR="syswow64"; else SYSDIR="system32"; fi
    if ! command -v unzip >/dev/null; then echo "unzip is not available, cannot continue."; Quit; fi

    OVERRIDE_DLL="colorcnv dxva2 evr mf mferror mfplat mfplay mfreadwrite msmpeg2adec msmpeg2vdec sqmapi wmadmod wmvdecod"
    REGISTER_DLL="colorcnv evr msmpeg2adec msmpeg2vdec wmadmod wmvdecod"

    # install 32-bit components
    DownloadFileInternal mf mf32.zip 2600aeae0f0a6aa2d4c08f847a148aed7a09218f1bfdc237b90b43990644cbbd

    unzip -o -q -d "$WORKDIR/temp" "$WORKDIR/mf32.zip" || Quit;
    cp -vf "$WORKDIR/temp/syswow64"/* "$WINEPREFIX/drive_c/windows/$SYSDIR"

    OverrideDll winegstreamer ""
    for DLL in $OVERRIDE_DLL; do OverrideDll $DLL native; done

    RUN "c:/windows/$SYSDIR/reg" import "$WORKDIR/temp/mf.reg"
    RUN "c:/windows/$SYSDIR/reg" import "$WORKDIR/temp/wmf.reg"

    for DLL in $REGISTER_DLL; do RUN regsvr32 "c:/windows/$SYSDIR/$DLL.dll"; done

    # install 64-bit components .... not needed yet. skipping this part!
    if [ 1 -eq 0 ]; then
        DownloadFileInternal mf mf64.zip 000000

        unzip -o -q -d "$WORKDIR/temp" "$WORKDIR/mf64.zip" || Quit;
        cp -vf "$WORKDIR/temp/system32"/* "$WINEPREFIX/drive_c/windows/system32"

        for DLL in $REGISTER_DLL; do RUN regsvr32 "c:/windows/system32/$DLL.dll"; done

        RUN "c:/windows/system32/reg" import "$WORKDIR/temp/mf.reg"
        RUN "c:/windows/system32/reg" import "$WORKDIR/temp/wmf.reg"
    fi

    # cleanup
    rm -fr "$WORKDIR/temp"
}

Install_quartz2()
{
    Heading "quartz2"

    DownloadFileInternal quartz2 quartz2.dll fa52a0d0647413deeef57c5cb632f73a97a48588c16877fc1cc66404c3c21a2b

    if [ $ARCH = "win64" ]; then SYSDIR="syswow64"; else SYSDIR="system32"; fi

    cp -fv "$SCRIPT_DIR/quartz2/quartz2.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/quartz2.dll"
    RUN regsvr32 quartz2.dll

    OverrideDll winegstreamer ""

    # use wine's quartz for these DirectShow filters
    DLL="c:/windows/$SYSDIR/quartz.dll"
    SetClassDll32 "79376820-07D0-11CF-A24D-0020AFD79767" $DLL #DirectSound
    SetClassDll32 "6BC1CFFA-8FC1-4261-AC22-CFB4CC38DB50" $DLL #DefaultVideoRenderer
    SetClassDll32 "70E102B0-5556-11CE-97C0-00AA0055595A" $DLL #VideoRenderer
    SetClassDll32 "51B4ABF3-748F-4E3B-A276-C828330E926A" $DLL #VMR9
    SetClassDll32 "B87BEB7B-8D29-423F-AE4D-6582C10175AC" $DLL #VMR7
}

Install_wmp11()
{
    Heading "wmp11"

    PREV_OSVER=$OSVER
    case $ARCH in
        win32) wmf="wmfdist11.exe";    validhash=ddfea7b588200d8bb021dbf1716efb9f63029a0dd016d4c12db89734852e528d;;
        win64) wmf="wmfdist11-64.exe"; validhash=eba63fa648016f3801e503fc91d9572b82aeb0409e73c27de0b4fbc51e81e505;;
        *) Quit;;
    esac

    DownloadFileInternal wmp11 $wmf $validhash

    SetWindowsVer winxp
    OverrideDll qasf native
    OverrideDll winegstreamer ""

    RUN "$SCRIPT_DIR/wmp11/$wmf" /q

    SetWindowsVer $PREV_OSVER
}

Install_xaudio29()
{
    Heading "xaudio29"

    DownloadFileInternal xaudio29 xaudio2_9.dll 667787326dd6cc94f16e332fd271d15aabe1aba2003964986c8ac56de07d5b57

    if [ $ARCH = "win64" ]; then SYSDIR="syswow64"; else SYSDIR="system32"; fi

    cp -fv "$SCRIPT_DIR/xaudio29/xaudio2_9.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/xaudio2_9.dll"
    cp -fv "$SCRIPT_DIR/xaudio29/xaudio2_9.dll" "$WINEPREFIX/drive_c/windows/$SYSDIR/xaudio2_8.dll"

    OverrideDll xaudio2_9 native
    OverrideDll xaudio2_8 native
}

Install_lavfilters()
{
    Heading "LAVFilters"

    FNAME="LAVFilters-0.77.2-Installer.exe"
    DownloadFile lavfilters $FNAME "https://github.com/Nevcairiel/LAVFilters/releases/download/0.77.2/LAVFilters-0.77.2-Installer.exe" 3bf333bae56f9856fb7db96ce2410df1da3958ac6a9fd5ac965d33c7af6f27d7

    RUN "$SCRIPT_DIR/lavfilters/$FNAME" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-

    RUN reg add "HKCU\\Software\\LAV\\Audio\\Formats" /f /t REG_DWORD /v wmalossless /d 1
}

# ============================================================================

VERBS="lavfilters mf quartz2 wmp11 xaudio29"

RunActions()
{
    declare -A REQ
    for item in $VERBS; do REQ[$item]=0; done

    for item in $@; do
        if [ "${REQ[$item]}" = 0 ]; then REQ[$item]=1;
        else echo "invalid verb $item"; Quit; fi
    done

    CheckEnv
    GetWindowsVer

    if [ ${REQ[quartz2]} = 1 ]; then Install_quartz2; fi
    if [ ${REQ[wmp11]} = 1 ]; then Install_WMP11; fi
    if [ ${REQ[mf]} = 1 ]; then Install_mf; fi
    if [ ${REQ[xaudio29]} = 1 ]; then Install_xaudio29; fi
    if [ ${REQ[lavfilters]} = 1 ]; then Install_lavfilters; fi
}

if [ $# -gt 0 ]; then
    RunActions $@
else
    echo "Specify one or more of these verbs to install them:"
    echo $VERBS
    echo
fi
