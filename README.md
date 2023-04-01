# About weapon_vote
The plugin adds the ability to get weapons by voting.

## Commands
`!<weapon>` - get <weapon>. See `config/weapon_vote.ini` "<Chat/Console command>"

## How to add weapons?
To add a weapon to the list, edit the `config/weapon_vote.ini` file. 

Sample: `"<Weapon const (weapon_*)>" "<Name in vote title>" "<Chat/Console command>"`.
Example:
```
"weapon_sniper_scout"  "Scout"   "scout"; Adds a Scout, available with the !scout command.
"weapon_pistol_magnum" "Magnum" "magnum"; Adds a Magnum, available with the !magnum command.
```

## Require
[NativeVotes](https://github.com/sapphonie/sourcemod-nativevotes-updated)

## Support
[ReadyUp](https://github.com/SirPlease/L4D2-Competitive-Rework/blob/master/addons/sourcemod/scripting/readyup.sp)
