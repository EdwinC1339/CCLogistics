# Minecraft Logistics Management system for CC Tweaked and Create

The startup.lua included here is written for lua 5.4 for testing purposes, which is not compatible with the libraries used unmodified. For this reason, take an extra step when importing to CC: export the original statemachine.lua from the linked repository into pastebin, save it into CC, then export statemachine.lua into pastebin and import into CC.

## Export Script

I included a script for automatically exporting to pastebin.  
Usage: `python export.py <YOUR DEV KEY> <FILENAME>`

## Acknowlegments

Credit to [lua-state-machine](https://github.com/kyleconroy/lua-state-machine) for the state machine micro-framework.
