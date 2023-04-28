# About vs_weapon_vote
The plugin adds the ability to get weapons by voting.

## Commands
`!<weapon>` - get "weapon" (!scout).

## How to add weapons?
To add a weapon to the list, edit the `config/vs_weapon_vote.txt` file. 

Example:
```
"Weapons"
{
	"weapon_sniper_scout"
	{
		"cmd" "sm_scout"
		"cmd" "sm_sniper"
	}

  	"weapon_smg"
	{
		"cmd" "sm_uzi"
	}
}
```

## Require
[NativeVotesRework](https://github.com/TouchMe-Inc/l4d2_nativevotes_rework)

## Support
ReadyUp
