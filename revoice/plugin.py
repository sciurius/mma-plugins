# We import the plugin utilities
from MMA import pluginUtils as pu

import datetime
from MMA.common import error, warning
from MMA.macro import macros
import MMA.gbl as gbl
import MMA.chordtable as chordtable
from MMA.chords import ChordNotes
import re
import random

# MMA required version.
pu.setMinMMAVersion(19, 7)

# A short plugin description.
pu.setDescription("""This plugin
processes a line of input and returns the line with
all chords revoiced.
""")

author = "Johan Vromans"
# A short author line.
pu.setAuthor("Written by {}".format(author))

try:
    pu.setSynopsis("""
    21 @revoice Cm D
    22 @revoice Cm7 Fm7
       @revoice Gm7

    or

    @revoice 21 Cm D
    @revoice 22 Cm7 Fm7

    DO NOT USE WITH Begin/End -- IT WILL DIE!

    # So no not do this!
    Begin @revoice
        21 Cm D
    End
""")
except:
    pass

pu.setPluginDoc("""
Revoicing means that additional harmonics are added for the chords
to sound fuller, and subsequent chords may sound slightly different.
This is most interesting for slow music with long chords.
""")

# Usage message.
def printUsage():
        pu.printUsage()

# Entry point for simple "@revoice ..." case.
def run(line):
    # Check for leading line number.
    if line[0].isdigit():
        res = [ line[0] ]
        line = line[1:]
    else:
        res = [ '' ]
        
    res.extend( dataRun(line) )

    # run() must use pu.sendCommands.
    pu.addCommand(" ".join(res))
    pu.sendCommands()

# Entry point for " 1 @revoice ..." case.
def dataRun(line):
    res = []
    cp = re.compile("([A-G][b#]?)(.*)$")

    for arg in line:
        m = cp.match(arg)
        if m is None:
            res.append(arg)
            continue
        root = m.group(1)
        type = m.group(2)
        if len(type) == 0:
            type = "M"

        # print(">> " + arg + " " + root + " " + type)
        
        # Using C as root, get the chord data.
        ch = ChordNotes("C" + type);
        c = ch.chordType

        # print("Chord: %s (%s %s)" % ( ch.name, ch.tonic, ch.chordType ) )
        # print("NoteList: %s" % ' '.join(map(str, ch.noteList)))
        # print("ScaleList: %s" % ' '.join(map(str, ch.scaleList)))

        chordlist = chordtable.chordlist
        notelist  = chordlist[c][0]
        scale     = chordlist[c][1]
        
        n = list(notelist)
        for j in random.choice(((0,1),(0,2),(1,2))):
            n.append(n[j]+12)

        rvcnt = nextval()
        type = "{}-{}".format(c, rvcnt)
        chordlist[type] = (n, scale, "Revoiced")
        pu.addCommand("PrintChord {}".format(type))

        res.append(root + type)

    # dataRun() must return a line array, not including line number.
    return res
    
def nextval():
    #nextval.cnt += 1
    return nextval.cnt
    
nextval.cnt = 0
    
