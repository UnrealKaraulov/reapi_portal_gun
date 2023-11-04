#include <amxmodx>
#include <fakemeta>
#include <reapi>
#include <hamsandwich>
#include <xs>

new const PLUGIN_NAME[] = "[ReAPI] Portal Gun";
new const PLUGIN_VERSION[] = "0.2b";
new const PLUGIN_AUTHOR[] = "bizon, ArKaNeMaN, karaulov";
//new const PLUGIN_ORIGINAL_URL[] = "https://dev-cs.ru/resources/1523/";

enum any: CvarsStruct
{
	CVAR_FLAG_AUTO_EQUIP[32],
	CVAR_COST
};

enum any: PortalTypeStruct
{
	PORTAL_PRIMARY,
	PORTAL_SECONDARY
};

enum any: PortalGunResourceStruct
{
	PG_MDL_VIEW,
	PG_MDL_PLAYER,
	//PG_MDL_WORLD,
	PG_MDL_PORTAL,
	PG_SND_SHOOT1,
	PG_SND_SHOOT2,
	PG_SND_CREATE_B,
	PG_SND_CREATE_O,
	PG_SPR_FLARE_RED,
	PG_SPR_FLARE_BLUE
};

new const g_szPortalGunResource[PortalGunResourceStruct][MAX_RESOURCE_PATH_LENGTH] =
{
	"models/portal_gun/v_portalgun.mdl",
	"models/portal_gun/p_portalgun.mdl",
	//"models/portal_gun/w_portalgun.mdl",
	"models/portal_gun/portal.mdl",
	"portal_gun/shoot1.wav",
	"portal_gun/shoot2.wav",
	"portal_gun/portal_b.wav",
	"portal_gun/portal_o.wav",
	"sprites/portal_gun/orange.spr",
	"sprites/portal_gun/blue.spr"
};

new const CHAT_PREFIX[] = "^1[^4Портальная пушка^1]";
new const PORTAL_CLASSNAME_1[] = "pg_ent_r";
new const PORTAL_CLASSNAME_2[] = "pg_ent_b";
const Float: g_flPortalGunCoolDownNextAttack = 0.5;

new
	Array: g_aKnifeAttackSound,
	bool: g_isChatCmdEnabled,
	bool: g_bIsPortalGunHas[MAX_PLAYERS+1],
	bool: g_bIsPortalGunSelected[MAX_PLAYERS+1],
	g_iSpriteFlareIndex[PortalTypeStruct],
	Float:g_flPortalAccessTime[MAX_PLAYERS+1],
	g_eUserEntPortal[MAX_PLAYERS+1][PortalTypeStruct],
	g_iIndexTextMsg,
	g_eCvar[CvarsStruct];

public plugin_precache()
{
	precache_model(g_szPortalGunResource[PG_MDL_VIEW]);
	precache_model(g_szPortalGunResource[PG_MDL_PLAYER]);
	//precache_model(g_szPortalGunResource[PG_MDL_WORLD]);
	precache_model(g_szPortalGunResource[PG_MDL_PORTAL]);

	precache_sound(g_szPortalGunResource[PG_SND_SHOOT1]);
	precache_sound(g_szPortalGunResource[PG_SND_SHOOT2]);
	precache_sound(g_szPortalGunResource[PG_SND_CREATE_B]);
	precache_sound(g_szPortalGunResource[PG_SND_CREATE_O]);

	g_iSpriteFlareIndex[PORTAL_PRIMARY] = precache_model(g_szPortalGunResource[PG_SPR_FLARE_RED]);
	g_iSpriteFlareIndex[PORTAL_SECONDARY] = precache_model(g_szPortalGunResource[PG_SPR_FLARE_BLUE]);

	new const szKnifeAttackSound[] =
	{
		"weapons/knife_hit1.wav",
		"weapons/knife_hit2.wav",
		"weapons/knife_hit3.wav",
		"weapons/knife_hit4.wav",
		"weapons/knife_hitwall1.wav",
		"weapons/knife_slash1.wav",
		"weapons/knife_slash2.wav",
		"weapons/knife_stab.wav"
	};

	g_aKnifeAttackSound = ArrayCreate(MAX_RESOURCE_PATH_LENGTH);

	for(new i; i < sizeof(szKnifeAttackSound); i++)
		ArrayPushString(g_aKnifeAttackSound, szKnifeAttackSound[i]);
}

public client_disconnected(pPlayer)
{
	@portal_cleanup(pPlayer);
}

public plugin_init()
{
	register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

	RegisterHam(Ham_CS_Item_CanDrop, "weapon_knife", "@fwHam_KnifeItem_CanDrop_Pre", false);
	RegisterHam(Ham_Item_Deploy, "weapon_knife", "@fwHam_KnifeDeploy_Post", true);
	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_knife", "@fwHam_KnifePrimaryAttack_Post", true);
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_knife", "@fwHam_KnifeSecondaryAttack_Post", true);

	RegisterHookChain(RG_CSGameRules_PlayerSpawn, "@CSGameRules_PlayerSpawn_Post", true);
	RegisterHookChain(RG_CBasePlayer_TakeDamage, "@CBasePlayer_TakeDamage_Pre", false);

	register_forward(FM_EmitSound, "@fwd_EmitSound_Pre", false);

	register_clcmd("say /pg", "@pg_buy");
	register_clcmd("say_team /pg", "@pg_buy");
	register_clcmd("say /portalgun", "@pg_buy");
	register_clcmd("say_team /portalgun", "@pg_buy");
	register_clcmd("say /portal_gun", "@pg_buy");
	register_clcmd("say_team /portal_gun", "@pg_buy");

	g_iIndexTextMsg = get_user_msgid("TextMsg");

	@cvars_attach();
}

@fwHam_KnifeItem_CanDrop_Pre(iItem)
{
	new pPlayer;
	pPlayer = get_member(iItem, m_pPlayer);

	if(!is_user_connected(pPlayer) || !g_bIsPortalGunHas[pPlayer])
		return HAM_IGNORED;

	g_bIsPortalGunSelected[pPlayer] = !g_bIsPortalGunSelected[pPlayer];
	ExecuteHamB(Ham_Item_Deploy, iItem);

	set_msg_block(g_iIndexTextMsg, BLOCK_ONCE);
	return HAM_SUPERCEDE;
}

@fwHam_KnifeDeploy_Post(iItem)
{
	new pPlayer;
	pPlayer = get_member(iItem, m_pPlayer);

	if(!is_user_connected(pPlayer) || !g_bIsPortalGunSelected[pPlayer])
		return;

	set_entvar(pPlayer, var_viewmodel, g_szPortalGunResource[PG_MDL_VIEW]);
	set_entvar(pPlayer, var_weaponmodel, g_szPortalGunResource[PG_MDL_PLAYER]);
}

@fwHam_KnifePrimaryAttack_Post(iItem)
{
	new pPlayer;
	pPlayer = get_member(iItem, m_pPlayer);

	if(!is_user_connected(pPlayer) || !g_bIsPortalGunSelected[pPlayer])
		return;

	@create_portal_pre(pPlayer, true);
	emit_sound(pPlayer, CHAN_STATIC, g_szPortalGunResource[PG_SND_SHOOT1], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	set_member(pPlayer, m_flNextAttack, g_flPortalGunCoolDownNextAttack);
}

@fwHam_KnifeSecondaryAttack_Post(iItem)
{
	new pPlayer;
	pPlayer = get_member(iItem, m_pPlayer);

	if(!is_user_connected(pPlayer) || !g_bIsPortalGunSelected[pPlayer])
		return;

	@create_portal_pre(pPlayer, false);
	emit_sound(pPlayer, CHAN_STATIC, g_szPortalGunResource[PG_SND_SHOOT2], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	set_member(pPlayer, m_flNextAttack, g_flPortalGunCoolDownNextAttack);
}

@CSGameRules_PlayerSpawn_Post(pPlayer)
{
	if(!is_user_alive(pPlayer)) // i ne govori, 4to ne nado
		return;

	if(get_user_flags(pPlayer) & read_flags(g_eCvar[CVAR_FLAG_AUTO_EQUIP]))
		g_bIsPortalGunHas[pPlayer] = true;

	if(g_bIsPortalGunHas[pPlayer])
		@show_hud_info(pPlayer);
}

@CBasePlayer_TakeDamage_Pre(pVictim, eInflictor, pKiller, Float: fDamage, bitsDamageType)
{
	if(is_user_connected(pKiller) && g_bIsPortalGunSelected[pKiller])
	{
		SetHookChainReturn(ATYPE_INTEGER, 0);
		return HAM_SUPERCEDE;
	}

	return HC_CONTINUE;
}

@fwd_EmitSound_Pre(pPlayer, iChannel, const sSound[], Float: fVolume, Float: fAttenuation, iFlags, iPitch)
{
	if(!is_user_connected(pPlayer) || !g_bIsPortalGunSelected[pPlayer] || ArrayFindString(g_aKnifeAttackSound, sSound) == -1)
		return FMRES_IGNORED;

	return FMRES_SUPERCEDE;
}

@pg_buy(pPlayer)
{
	if (!g_isChatCmdEnabled)
		return;

	if(g_eCvar[CVAR_FLAG_AUTO_EQUIP][0] != EOS && get_user_flags(pPlayer) & read_flags(g_eCvar[CVAR_FLAG_AUTO_EQUIP]))
	{
		client_print_color(pPlayer, print_team_default, "%s У вас уже есть этот предмет", CHAT_PREFIX);
		return;
	}

	if(g_eCvar[CVAR_COST] == -1)
	{
		client_print_color(pPlayer, print_team_default, "%s Покупка предмета отключена", CHAT_PREFIX);
		return;
	}

	if(get_member(pPlayer, m_iAccount) < g_eCvar[CVAR_COST])
	{
		client_print_color(pPlayer, print_team_default, "%s У вас не хватает денег", CHAT_PREFIX);
		return;
	}

	rg_add_account(pPlayer, -g_eCvar[CVAR_COST]);
	g_bIsPortalGunHas[pPlayer] = true;

	@show_hud_info(pPlayer);
}

@create_portal_pre(pPlayer, bool: bIsPrimaryAttack)
{
	new
		Float: vecOrigin[3],
		Float: vecOriginTeleport[3],
		Float: vecAngles[3],
		Float: vecAnglesTeleport[3];

	if(!@is_get_origin_aiming_place_accuracy(pPlayer, vecOrigin, vecAngles, vecOriginTeleport, vecAnglesTeleport, bIsPrimaryAttack))
	{
		new Float: vecOriginUp[3];

		vecOriginUp = vecOrigin;
		vecOriginUp[2] += 50.0;
		set_msg_spritetrail(vecOrigin, vecOriginUp, g_iSpriteFlareIndex[bIsPrimaryAttack ? PORTAL_PRIMARY : PORTAL_SECONDARY], 25, 2, 2, 25, 20);
	}
	else
	{
		@create_portal_post(pPlayer, vecOrigin, vecAngles, vecOriginTeleport, vecAnglesTeleport, bIsPrimaryAttack);
		emit_sound(pPlayer, CHAN_STATIC, g_szPortalGunResource[PG_SND_CREATE_B], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
	}
}

@create_portal_post(pPlayer, Float: vecOrigin[3], Float: vecAngles[3], Float: vecOriginTeleport[3], Float: vecAnglesTeleport[3], bool: bIsPrimary)
{
	new eEnt;
	eEnt = rg_create_entity("info_target");

	engfunc(EngFunc_SetModel, eEnt, g_szPortalGunResource[PG_MDL_PORTAL]);
	engfunc(EngFunc_SetSize, eEnt, Float: { -2.0, -30.0, -40.0 }, Float: { 2.0, 30.0, 40.0 });
	engfunc(EngFunc_SetOrigin, eEnt, vecOrigin);

	set_entvar(eEnt, var_classname, bIsPrimary ? PORTAL_CLASSNAME_1 : PORTAL_CLASSNAME_2);
	set_entvar(eEnt, var_movetype, MOVETYPE_FLY);
	set_entvar(eEnt, var_solid, SOLID_TRIGGER);
	set_entvar(eEnt, var_angles, vecAngles);
	set_entvar(eEnt, var_iuser3, pPlayer);
	set_entvar(eEnt, var_iuser4, bIsPrimary);
	set_entvar(eEnt, var_vuser1, vecOriginTeleport);
	set_entvar(eEnt, var_vuser2, vecAnglesTeleport);

	if(bIsPrimary)
	{
		if(!is_nullent(g_eUserEntPortal[pPlayer][PORTAL_PRIMARY]))
			rg_remove_entity(g_eUserEntPortal[pPlayer][PORTAL_PRIMARY]);

		g_eUserEntPortal[pPlayer][PORTAL_PRIMARY] = eEnt;
		set_entvar(eEnt, var_skin, 0);
	}
	else
	{
		if(!is_nullent(g_eUserEntPortal[pPlayer][PORTAL_SECONDARY]))
			rg_remove_entity(g_eUserEntPortal[pPlayer][PORTAL_SECONDARY]);

		g_eUserEntPortal[pPlayer][PORTAL_SECONDARY] = eEnt;
		set_entvar(eEnt, var_skin, 1);
	}

	SetTouch(eEnt, "@portal_touch");
}

@portal_touch(eEnt, pPlayer)
{
	if(is_nullent(eEnt))
		return;
		
	new bool: bIsPlayer;
	bIsPlayer = is_user_connected(pPlayer) > 0;
	
	new bool: bIsValidEntity;
	bIsValidEntity = !bIsPlayer && !is_nullent(pPlayer);
	
	if (bIsValidEntity)
	{
		new sClassName[64];
		get_entvar(pPlayer, var_classname, sClassName,charsmax(sClassName));
		// Если не граната то не пропускать
		if (!equal(sClassName,"grenade"))
			bIsValidEntity = false;
	}
	
	if (!bIsPlayer && !bIsValidEntity)
		return;

	new Float: fGameTime;
	fGameTime = get_gametime();
	
	// Разрешить небольшие зацикливания для игрока (не чаще чем 0.5 сек)
	if( bIsValidEntity || (bIsPlayer && floatabs(g_flPortalAccessTime[pPlayer] - fGameTime) > 0.5) )
	{
		new pOwner;
		pOwner = get_entvar(eEnt, var_iuser3);

		if(is_user_connected(pOwner))
		{
			new ePortalEnt;
			ePortalEnt = NULLENT;

			if(get_entvar(eEnt, var_iuser4))
			{
				if(!is_nullent(g_eUserEntPortal[pOwner][PORTAL_SECONDARY]))
					ePortalEnt = g_eUserEntPortal[pOwner][PORTAL_SECONDARY];
			}
			else
			{
				if(!is_nullent(g_eUserEntPortal[pOwner][PORTAL_PRIMARY]))
					ePortalEnt = g_eUserEntPortal[pOwner][PORTAL_PRIMARY];
			}

			if(is_nullent(ePortalEnt))
			{
				if (bIsPlayer)
				{
					g_flPortalAccessTime[pPlayer] = fGameTime;
				}
				return;
			}

			new Float: vecOriginTeleport[3];
			get_entvar(ePortalEnt, var_vuser1, vecOriginTeleport);
			
			new Float: vecOriginBase[3];
			get_entvar(eEnt, var_origin, vecOriginBase);
			
			new Float: vecOriginOffset[3];
			get_entvar(pPlayer, var_origin, vecOriginOffset);
			
			new Float: vecTest[3];
			
			vecTest[2] = vecOriginTeleport[2];
			
			for (new i = 0; i < 2; i++) {
				vecTest[i] = floatabs(vecOriginOffset[i] - vecOriginBase[i]);
				if (vecTest[i] > 46.0)
					vecTest[i] = 46.0;
			}
			for (new i = 0; i < 2; i++) {
				vecTest[i] = vecOriginTeleport[i] - vecTest[i];
			}
			
			if(is_hull_vacant(vecTest, HULL_HUMAN, pPlayer))
			{
				vecOriginTeleport = vecTest;
			}
			else 
			{
				for (new i = 0; i < 2; i++) {
					vecTest[i] = floatabs(vecOriginOffset[i] - vecOriginBase[i]);
					if (vecTest[i] > 46.0)
						vecTest[i] = 46.0;
				}
				
				for (new i = 0; i < 2; i++) {
					vecTest[i] = vecOriginTeleport[i] + vecTest[i];
				}
			
				if(is_hull_vacant(vecTest, HULL_HUMAN, pPlayer))
				{
					vecOriginTeleport = vecTest;
				}
				else 
				{
					if (bIsPlayer)
					{
						g_flPortalAccessTime[pPlayer] = fGameTime;
					}
					return;
				}
			}
			
			set_entvar(pPlayer, var_origin, vecOriginTeleport);
			
			// Получение всего что надо
			new Float:vecInAngle[3];
			get_entvar(eEnt, var_vuser2, vecInAngle);
			new Float:vecOutAngle[3];
			get_entvar(ePortalEnt, var_vuser2, vecOutAngle);
			new Float:vecPlayerVel[3];
			get_entvar(pPlayer, var_velocity, vecPlayerVel);
			new Float:vecPlayerAngle[3];
			get_entvar(pPlayer, var_angles, vecPlayerAngle);
			new Float:vecPlayerVAngle[3];
			get_entvar(pPlayer, var_v_angle, vecPlayerVAngle);
			
			// Просчёт и установка вектора движения игрока
			new Float:vecOutVel[3];
			@pg_vec_GetOutVel(vecInAngle, vecOutAngle, vecPlayerVel, vecOutVel);
			set_entvar(pPlayer, var_velocity, vecOutVel);
			
			// Просчёт и установка угла поворота
			new Float:vecResAngle[3];
			@pg_vec_getOutAngle(vecInAngle, vecOutAngle, vecPlayerAngle, vecResAngle);
			vecResAngle[0] = vecPlayerVAngle[0];
			
			set_entvar(pPlayer, var_angles, vecResAngle);
			set_entvar(pPlayer, var_v_angle, vecResAngle);
			
			set_entvar(pPlayer, var_fixangle, 1);
			
			emit_sound(pPlayer, CHAN_STATIC, g_szPortalGunResource[PG_SND_CREATE_O], VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
		}
		if (bIsPlayer)
		{
			g_flPortalAccessTime[pPlayer] = fGameTime;
		}
	}
}

bool: @is_get_origin_aiming_place_accuracy(pPlayer, Float: vecOrigin[3], Float: vecAngles[3], Float: vecOriginTeleport[3], Float: vecAnglesTeleport[3], bool: bIsPrimaryAttack)
{
	const Float: flOriginShiftValueCreate = 2.0;
	const Float: flOriginShiftValueTeleport = 60.0;

	new
		Float: vecDest[3],
		Float: vecDest2[3];

	get_entvar(pPlayer, var_origin, vecOrigin);
	get_entvar(pPlayer, var_view_ofs, vecDest2);

	vecDest = vecOrigin;
	xs_vec_add(vecOrigin, vecDest2, vecOrigin);

	get_entvar(pPlayer, var_v_angle, vecDest2);
	engfunc(EngFunc_MakeVectors, vecDest2);
	global_get(glb_v_forward, vecDest2);

	xs_vec_mul_scalar(vecDest2, 8192.0, vecDest2);
	xs_vec_add(vecOrigin, vecDest2, vecDest2);

	engfunc(EngFunc_TraceLine, vecOrigin, vecDest2, DONT_IGNORE_MONSTERS, pPlayer, 0);
	get_tr2(0, TR_vecEndPos, vecOrigin);

	new eFindEnt;
	eFindEnt = NULLENT;

	while((eFindEnt = engfunc(EngFunc_FindEntityInSphere, eFindEnt, vecOrigin, 40.0)))
	{
		if(!is_nullent(eFindEnt) && 
		(
		(FClassnameIs(eFindEnt, PORTAL_CLASSNAME_1) && !bIsPrimaryAttack) || 
		(FClassnameIs(eFindEnt, PORTAL_CLASSNAME_2) && bIsPrimaryAttack) 
		))
		{
			return false;
		}
	}

	get_tr2(0, TR_vecPlaneNormal, vecDest2);
	xs_vec_add_scaled(vecOrigin, vecDest2, flOriginShiftValueTeleport, vecOriginTeleport);
	xs_vec_add_scaled(vecOrigin, vecDest2, flOriginShiftValueCreate, vecOrigin);

	engfunc(EngFunc_VecToAngles, vecDest2, vecAngles);

	if(vecDest2[2] >= -0.5 && vecDest2[2] <= 0.5)
		vecAnglesTeleport = vecAngles;
	else
		xs_vec_neg(vecAngles, vecAnglesTeleport);

	return is_hull_vacant(vecOriginTeleport, HULL_HUMAN, pPlayer);
}

@show_hud_info(pPlayer)
{
	set_hudmessage(0, 255, 0, -1.0, 0.25, .holdtime = 10.0);
	show_hudmessage(pPlayer, "Для смены на портальную пушку^nВыберите нож и нажмите G");
}

@cvars_attach()
{
	bind_pcvar_string(
		create_cvar(
			"pg_flags_access", "d", FCVAR_SERVER,
			.description = "Флаг или флаги доступа к бесплатной выдаче портальной пушки\
			^nОставьте настройку пустой, чтобы не было автоматической выдачи",
			.has_min = false, .min_val = 0.0,
			.has_max = false, .max_val = 0.0
		), g_eCvar[CVAR_FLAG_AUTO_EQUIP], charsmax(g_eCvar[CVAR_FLAG_AUTO_EQUIP])
	);

	bind_pcvar_num(
		create_cvar(
			"pg_cost", "16000", FCVAR_SERVER,
			.description = "Стоимость покупки портальной пушки\
			^nУстановите значение `-1`, чтобы отключить возможность покупки",
			.has_min = false, .min_val = 0.0,
			.has_max = false, .max_val = 0.0
		), g_eCvar[CVAR_COST]
	);

	AutoExecConfig(true, "reapi_portal_gun");
}

@portal_cleanup(pPlayer)
{
	if(!is_nullent(g_eUserEntPortal[pPlayer][PORTAL_PRIMARY]))
		rg_remove_entity(g_eUserEntPortal[pPlayer][PORTAL_PRIMARY]);

	if(!is_nullent(g_eUserEntPortal[pPlayer][PORTAL_SECONDARY]))
		rg_remove_entity(g_eUserEntPortal[pPlayer][PORTAL_SECONDARY]);

	g_eUserEntPortal[pPlayer][PORTAL_PRIMARY] = NULLENT;
	g_eUserEntPortal[pPlayer][PORTAL_SECONDARY] = NULLENT;

	g_bIsPortalGunHas[pPlayer] = false;
	g_bIsPortalGunSelected[pPlayer] = false;
}

public plugin_natives()
{
	register_native("pg_chat_command", "@pg_chat_command")
	register_native("pg_player_give", "@pg_player_give")
	register_native("pg_player_drop", "@pg_player_drop")
	register_native("pg_is_has_player", "@pg_is_has_player")
}

@pg_chat_command(bool:enable)
{
	g_isChatCmdEnabled = enable;
}

@pg_player_give(pPlayer)
{
	enum any: { arg_player = 1 };

	new pPlayer;
	pPlayer = get_param(arg_player);

	if(!is_user_connected(pPlayer))
	{
		log_amx("Невалидный индекс игрока для выдачи пушки (native: `pg_player_give`)");
		return;
	}

	g_bIsPortalGunHas[pPlayer] = true;
	@show_hud_info(pPlayer);
}

@pg_player_drop(pPlayer)
{
	enum any: { arg_player = 1 };

	new pPlayer;
	pPlayer = get_param(arg_player);

	if(pPlayer > 0 && pPlayer < 33)
	{
		g_bIsPortalGunHas[pPlayer] = false;
		@portal_cleanup(pPlayer);
		return;
	}
	
	log_amx("Невалидный индекс игрока для удаления пушки (native: `pg_player_give`)");
}

@pg_is_has_player(pPlayer)
{
	enum any: { arg_player = 1 };

	new pPlayer;
	pPlayer = get_param(arg_player);

	if(!is_user_connected(pPlayer))
	{
		log_amx("Невалидный индекс игрока для проверки наличия пушки (native: `pg_is_has_player`)");
		return -1;
	}

	return g_bIsPortalGunHas[pPlayer];
}

// Получение угла поворота игрока после прохождения через портал
@pg_vec_getOutAngle(
	const Float:vecInAngle[3],  // Угол входного портала
	const Float:vecOutAngle[3], // Угол выходного портала
	const Float:vecSrcAngle[3], // Входной вектор движения игрока
	Float:vecResAngle[3]
) {
	for (new i = 0; i < 2; i++) {
		vecResAngle[i] = (vecSrcAngle[i] - vecInAngle[i] + vecOutAngle[i] ) - 180;
	}
}
// Получение вектора движения игрока после прохождения через портал
@pg_vec_GetOutVel(
	const Float:vecInAngle[3],  // Угол входного портала
	const Float:vecOutAngle[3], // Угол выходного портала
	Float:vecSrcVel[3],   // Входной вектор движения игрока
	Float:vecOutVel[3]
) {
	new Float:fSrcSpeed = vector_length(vecSrcVel);
	
	if (floatabs(360.0 + vecInAngle[0] + vecOutAngle[0]) <= 91.0)
		vecSrcVel[2] *= -1.0;
	
	if (xs_fsign(fSrcSpeed) != -1)
	{
		// Минимальная скорость падения игрока	
		if (fSrcSpeed < 200.0)
			fSrcSpeed = 200.0;
			
		// Максимальная скорость падения игрока
		if (fSrcSpeed > 500.0)
			fSrcSpeed = 500.0;
	}
	else 
	{
		// Минимальная скорость падения игрока	
		if (fSrcSpeed > -200.0)
			fSrcSpeed = -200.0;
			
		// Максимальная скорость падения игрока
		if (fSrcSpeed < -500.0)
			fSrcSpeed = -500.0;
	}
	new Float:vecSrcDir[3];
	for (new i = 0; i < 3; i++) {
		vecSrcDir[i] = -(vecSrcVel[i] / fSrcSpeed);
	}
	new Float:vecSrcAngle[3];
	vector_to_angle(vecSrcDir, vecSrcAngle);
	new Float:vecAnglesDiff[3];
	for (new i = 0; i < 3; i++) {
		vecAnglesDiff[i] = vecSrcAngle[i] - vecInAngle[i] + vecOutAngle[i];
	}
	angle_vector(vecAnglesDiff, ANGLEVECTOR_FORWARD, vecOutVel);
	for (new i = 0; i < 3; i++) {
		vecOutVel[i] *= fSrcSpeed;
	}
}

stock rg_remove_entity(eEnt)
{
	set_entvar(eEnt, var_flags, FL_KILLME);
	set_entvar(eEnt, var_nextthink, -1);
}

stock bool:is_hull_vacant(Float: vecOrigin[3], iHull, eEnt)
{
	engfunc(EngFunc_TraceHull, vecOrigin, vecOrigin, DONT_IGNORE_MONSTERS, iHull, eEnt, 0);

	return !get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen);
}

stock set_msg_spritetrail(Float: vecOriginStart[3], Float: vecOriginEnd[3], iSprite, iCount, iLife, iScale, iVelocity, iRandomness)
{
	message_begin_f(MSG_PAS, SVC_TEMPENTITY, vecOriginStart, 0);
	write_byte(TE_SPRITETRAIL);
	write_coord_f(vecOriginStart[0]);
	write_coord_f(vecOriginStart[1]);
	write_coord_f(vecOriginStart[2]);
	write_coord_f(vecOriginEnd[0]);
	write_coord_f(vecOriginEnd[1]);
	write_coord_f(vecOriginEnd[2]);
	write_short(iSprite);
	write_byte(iCount);
	write_byte(iLife);
	write_byte(iScale);
	write_byte(iVelocity);
	write_byte(iRandomness);
	message_end();
}
