#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\system_shared;

#insert scripts\shared\shared.gsh;

#namespace clientids;

REGISTER_SYSTEM( "clientids", &__init__, undefined )

function __init__()
{
    callback::on_start_gametype( &init );
    callback::on_connect( &on_player_connect );
    callback::on_spawned( &on_player_spawned );
}

function init()
{
    // In LAN/offline sessions the engine can leave the script client id unset.
    level.clientid = 0;
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

function on_player_spawned()
{
    if ( !isdefined( self.bo3_qol_welcome_shown ) )
    {
        self.bo3_qol_welcome_shown = true;
        self IPrintLnBold( "Splitscreen QoL: Test-Build aktiv" );
    }
}
