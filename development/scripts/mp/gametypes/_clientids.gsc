#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\system_shared;
#using scripts\shared\util_shared;

#insert scripts\shared\shared.gsh;

#namespace clientids;

// Stock client id handling plus QoL match tracking. The frontend (Lua) reads
// the result from the dvar qol_last_match when the lobby is shown again.
//
// Report format (records separated by ';'):
//   v1;t=<time>;gt=<gametype>;map=<map>
//   ts=<team>,<score>                      (team based modes)
//   p=<ent>,<team>,<kills>,<deaths>,<headshots>,<score>,<bot 0/1>,<name>
//   k=<attackerEnt>_<victimEnt>,<count>    (only kills involving a human)

REGISTER_SYSTEM( "clientids", &__init__, undefined )

function __init__()
{
	callback::on_start_gametype( &init );
	callback::on_connect( &on_player_connect );
	callback::on_spawned( &qol_on_spawned );
}

function init()
{
	// this is now handled in code ( not lan )
	level.clientid = 0;

	level.qol_kills = [];
	level thread qol_hook_player_killed();
	level thread qol_report_on_game_end();
}

function on_player_connect()
{
	self.clientid = matchRecordNewPlayer( self );
	if ( !isdefined( self.clientid ) || self.clientid == -1 )
	{
		self.clientid = level.clientid;
		level.clientid++;
	}
}

function qol_on_spawned()
{
	if ( isdefined( self.qol_info_shown ) )
		return;
	self.qol_info_shown = true;

	info = GetDvarString( "qol_round_info" );
	if ( isdefined( info ) && info != "" )
		self IPrintLnBold( info );
}

function qol_hook_player_killed()
{
	while ( !isdefined( level.callbackPlayerKilled ) )
		WAIT_SERVER_FRAME;

	level.qol_original_player_killed = level.callbackPlayerKilled;
	level.callbackPlayerKilled = &qol_player_killed;
}

function qol_player_killed( eInflictor, attacker, iDamage, sMeansOfDeath, weapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration, enteredResurrect = false )
{
	if ( game[ "state" ] != "postgame" )
		qol_send_obituary( attacker, sMeansOfDeath );

	if ( isdefined( attacker ) && IsPlayer( attacker ) && attacker != self )
	{
		if ( !( attacker util::is_bot() ) || !( self util::is_bot() ) )
		{
			key = attacker GetEntityNumber() + "_" + self GetEntityNumber();
			if ( !isdefined( level.qol_kills[ key ] ) )
				level.qol_kills[ key ] = 0;
			level.qol_kills[ key ]++;
		}
	}

	self [[ level.qol_original_player_killed ]]( eInflictor, attacker, iDamage, sMeansOfDeath, weapon, vDir, sHitLoc, psOffsetTime, deathAnimDuration, enteredResurrect );
}

// Killfeed for the QoL HUD (ui/qol/ingame.lua): attacker and victim client
// numbers plus flags 1 = headshot, 2 = melee, 4 = suicide. self == victim.
function qol_send_obituary( attacker, sMeansOfDeath )
{
	attackerNum = -1;
	if ( isdefined( attacker ) && IsPlayer( attacker ) )
		attackerNum = attacker GetEntityNumber();

	flags = 0;
	suicide = ( attackerNum == self GetEntityNumber() );
	if ( isdefined( sMeansOfDeath ) )
	{
		if ( sMeansOfDeath == "MOD_HEAD_SHOT" )
			flags += 1;
		if ( sMeansOfDeath == "MOD_MELEE" || sMeansOfDeath == "MOD_MELEE_WEAPON_BUTT" || sMeansOfDeath == "MOD_MELEE_ASSASSINATE" )
			flags += 2;
		if ( sMeansOfDeath == "MOD_SUICIDE" || sMeansOfDeath == "MOD_FALLING" || sMeansOfDeath == "MOD_TRIGGER_HURT" )
			suicide = true;
	}
	if ( suicide )
		flags += 4;

	LUINotifyEvent( &"qol_obit", 3, attackerNum, self GetEntityNumber(), flags );
}

function qol_stat( player, name )
{
	if ( isdefined( player.pers ) && isdefined( player.pers[ name ] ) )
		return player.pers[ name ];
	return 0;
}

function qol_clean( text )
{
	parts = StrTok( text, ";" );
	result = "";
	for ( i = 0; i < parts.size; i++ )
	{
		if ( i > 0 )
			result += "_";
		result += parts[ i ];
	}
	return result;
}

function qol_report_on_game_end()
{
	level waittill( "game_ended" );

	report = "v1;t=" + GetTime() + ";gt=" + level.gametype + ";map=" + GetDvarString( "mapname" );

	if ( level.teamBased )
	{
		foreach ( team in level.teams )
		{
			if ( isdefined( game[ "teamScores" ][ team ] ) )
				report += ";ts=" + team + "," + game[ "teamScores" ][ team ];
		}
	}

	foreach ( player in level.players )
	{
		team = "free";
		if ( isdefined( player.pers ) && isdefined( player.pers[ "team" ] ) )
			team = player.pers[ "team" ];

		bot = 0;
		if ( player util::is_bot() )
			bot = 1;

		report += ";p=" + player GetEntityNumber() + "," + team
			+ "," + qol_stat( player, "kills" )
			+ "," + qol_stat( player, "deaths" )
			+ "," + qol_stat( player, "headshots" )
			+ "," + qol_stat( player, "score" )
			+ "," + bot
			+ "," + qol_clean( player.name );
	}

	foreach ( key, count in level.qol_kills )
		report += ";k=" + key + "," + count;

	SetDvar( "qol_last_match", report );
}
