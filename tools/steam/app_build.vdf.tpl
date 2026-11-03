"AppBuild"
{
	"AppID" "@APP_ID@"
	"Desc" "@DESC@"
	"BuildOutput" "@OUT@"
	"ContentRoot" "@CONTENT@"
	"SetLive" "@BRANCH@"
	"Depots"
	{
		"@DEPOT_ID@"
		{
			"FileMapping"
			{
				"LocalPath" "*"
				"DepotPath" "."
				"recursive" "1"
			}
			"FileExclusion" "*.pdb"
			"FileExclusion" "steam_appid.txt"
		}
	}
}
