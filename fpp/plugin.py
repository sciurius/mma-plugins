# We import the plugin utilities
from MMA import gbl
from MMA import pluginUtils as pu
from MMA import parse
from MMA import macro
from MMA.timesig import timeSig
import re

# A short plugin description.
pu.setDescription("Define fingerpicking paterns.")

author = "Johan Vromans"
# A short author line.
pu.setAuthor("Written by {}".format(author))

pu.setTrackType('PLECTRUM')

pu.setSynopsis("""
  Track @fpp Pat, Seq, Debug

""")

# Note that pu.printUsage requires the default values to be strings. 
pu.addArgument( "Pat",    None,   "Pattern to define."  )
pu.addArgument( "Tab",    None,   "Pattern tab."        )
pu.addArgument( "Bpb",    '0',    "Beats per bar."      )
pu.addArgument( "Q",      '0',    "Beat length (8, 4)." )
pu.addArgument( "Debug",  '0',    "For debugging."      )

# We add a small doc. %NAME% is replaced by plugin name.
pu.setPluginDoc("""
This plugin creates fingerpicking patterns using ASCII tabs.

See https://github.com/sciurius/mma-plugins/blob/master/fpp/README.md for extensive documentation.

This plugin has been written by Johan Vromans <jvromans@squirrel.nl>
Version 1.00.
""")

# ###################################
# # Entry points                    #
# ###################################

# This prints help when MMA is called with -I switch.
def printUsage():
    pu.printUsage()

# Entry point for track plugin.
def trackRun( track, line ):
    args = pu.parseCommandLine(line)

    pat   = args["Pat"]
    tab   = args["Tab"]
    bpb   = int(args["Bpb"])
    q     = int(args["Q"])
    debug = int(args["Debug"])

    # Init bpb and q from timesig if needed.
    if bpb == 0 or q == 0:
        ( n, d) = timeSig.get()
        if bpb == 0: bpb = n
        if q == 0: q = 2**d;

    # The sequence data is a series of Instrument Pattern pairs.
    # It may be passed in a macro name.
    t = tab.split()
    if len(t) == 1:
        # Macro name.
        t = pu.getVar(tab.upper())
        # MSet macro return list of list. Flatten.
        if len(t) > 0 and isinstance(t[0], list):
            #print(t)
            res = []
            for item in t:
                if len(item) == 2 and item[0].upper() in "EADBG":
                    res.append(item[1])
                else:
                    if len(item) == 1:
                        res.append(item[0])
                    else:
                        res.append(item)
            t = res
            #print(t)
        else:
            # Single value macro. Split.
            t = t.split()

    string = len(t)
    tab = []

    #print(t)
    step = -1;
    for s in t:

        # Just in case we're quoted.
        if s[ 0] in "\"'": s = s[1:]
        if s[-1] in "\"'": s = s[:-1]

        # Drop leading string names.
        if s[0].upper() in 'EADGB': s = s[1:]

        # Verify (and drop) leading and trailing bars.
        if s[0] == '|' and s[-1] == '|': s = s[1:-1]
        else:
            raise Exception( "Missing | | in tab element: {}".format(s) )

        # Verify equal width (step size).
        if step < 0:
            step = len(s)
        else:
            if step != len(s):
                raise Exception( "Incorrect length item in tab element: |{}| {} <> {}".format(s,len(s),step) )

        tab.append(s)

    # tab now contains N elements (N = strings) each M long (step size).
    if debug: print("FPP: {}".format(tab))

    # Verify and calculate step delta.
    if step % bpb != 0:
        raise Exception( "Step size {} must be multiple of bpb {}".format(bpb,step) )
    # Force floats for python2.
    delta = ( bpb * 4.0 ) / ( q * step )
    if delta <= 0:
        raise Exception( "DELTA ERROR: {} {} {} {}".format(delta,bpb,q,step) )

    # Nice formatting.
    df = len("{:g}".format(delta))
    if df == 1: df = 0
    else:
        if df == 3: df = 1
        else: df = 2
    # To collect strings per step.
    res = []
    for i in range(step): res.append('')

    tm = 1
    for i in range(step):
        for j in range(string):
            x = tab[j][i]
            if x == '-': continue
            if res[i] == "":
                res[i] = "{:.{}f} 0 ".format(tm,df)
            res[i] += "{}:{} ".format( j+1, 10*int(x) )
        tm += delta

    cmd = "Define " + pat + " " + "; ".join([x for x in res if x])

    # Hackattack...
    # If we're called from a Begin Plectrum-Foo then we should not
    # include the track in the resultant command.
    beginData = parse.beginData
    if beginData and beginData[0].upper() == track:
        1
    else:
        cmd = track + " " + cmd

    if debug: print("FPP: " + cmd)
    pu.addCommand(cmd)

    pat = pat.upper()
    # Set picking pattern. Call after groove change.
    pu.addCommand("DefCall " + pat + " Chords")
    pu.addCommand(track + " Sequence " + pat)
    pu.addCommand("  1    $Chords")
    pu.addCommand("EndDefCall")
    pu.addCommand("Set " + pat + " Call " + pat)

    # if debug: print(pu._P().COMMANDS)

    # For convenience.
    if "PPSETUP" not in macro.macros.vars:
        pp = [ [ track, 'Voice', 'NylonGuitar' ],
               [ track, 'Volume', '100' ] ]
        if "RTIME" in macro.macros.vars:
            pp.append( [ track, 'RTime', macro.macros.vars["RTIME"] ] )
        if "RVOLUME" in macro.macros.vars:
            pp.append( [ track, 'RVolume', macro.macros.vars["RVOLUME"] ] )
        macro.macros.vars["PPSETUP"] = pp
        if debug: print("PPSETUP defined")

    pu.sendCommands()

# Produces an MMA sequence string from an ASCII tab.
def process_sequence( ix, tab ):

    print(tab)
    
    # Just in case we're quoted.
    if tab[ 0] in "\"'": tab = tab[1:]
    if tab[-1] in "\"'": tab = tab[:-1]
    if tab[0].upper() in 'EADGB': tab = tab[1:]
    print(tab)

    # Check validity.
    if len(tab) < 3 or tab[0] != '|' or tab[-1] != '|':
        raise Exception( "Invalid tab: {}".format(tab) )

    prev = ""
    res = ""

    m = re.finditer( r'([-0-9*]*)\|', tab[1:] )
    if m == None:
        raise Exception( "Not well-formed tab: {}".format(tab) )

    # Process the bars
    for x in m:
        bar = x.group(1)
        step = len(bar)
        if step == 0:
            # Empty bar: repeat previous.
            # If first: silent bar.
            if res != "":
                res = res + '/ '
            else:
                res = 'Z'
            continue

        # Single arsterisk copies existing sequence.
        if step == 1 and bar == '*':
            res = res + '* '
            continue

        seqs = []
        for index, char in enumerate(bar):
            if char == '-':
                continue
            t = "{:f}".format( 1 + index * bpb / step)
            # Strip unneeded trailing zeroes and decimal point.
            t = re.sub(r'\.?0+$', '', t)
            # Append.
            seqs.append( "{} 0 {:d}".format( t,
                                             int(round(int(char)*vscale))))

        if len(seqs) == 0:
            # Silent sequence.
            seq = "Z "
        else:
            # Combine.
            seq = "{ " + "; ".join(seqs) + " } "

        # Check for copies.
        if prev == seq:
            res = res + "/ "
        else:
            res = res + seq
            prev = seq

    return res

# Instrument names as used by Zoom percussion devices.
zoomNames = [
    "Kick",       "Snare",    "ClosedHat",  "OpenHat",
    "Crash",      "Ride",     "Tom1",       "Tom2",
    "Tom3",       "Stick",    "Bell",       "Maracas",
    "Tambourine", "LowConga", "MutHiConga", "OpenHiConga" ]

# Corresponding MMA percussion tones.
zoomTones = [
    "KickDrum1",    "SnareDrum1",  "ClosedHiHat",   "OpenHiHat",
    "CrashCymbal1", "RideCymbal1", "MidTom1",       "LowTom1",
    "HighTom1",     "SideKick",    "RideBell",      "Maracas",
    "Tambourine",   "LowConga",    "MuteHighConga", "OpenHighConga" ]
