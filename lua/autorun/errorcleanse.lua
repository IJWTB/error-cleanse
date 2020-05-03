if SERVER then
	AddCSLuaFile()
	resource.AddFile("models/props/smallcubetrt.mdl")
	resource.AddFile("materials/turtle/errorcleanse_opaque.vmt")
	resource.AddFile("materials/turtle/errorcleanse_opaque.vtf")
	resource.AddFile("materials/turtle/newmissing.vmt")
	resource.AddFile("materials/turtle/newmissing.vtf")
	return
end

if game.SinglePlayer() then
	return
end

local NewCube = ClientsideModel( 'models/props/smallcubetrt.mdl', RENDERGROUP_BOTH )
local NoGC = { NewCube }

local InvalidMins = Vector( -8, -38, 0 ) -- I wrote this code 2 years ago and I don't remember why I put this here.
local InvalidMaxs = Vector( 9, 44, 67 ) -- It's probably important for some reason.

NewCube:SetNoDraw( true )
NewCube:DrawShadow( false )

local function FloorVector( Vec )
	return Vector( math.floor( Vec.x ), math.floor( Vec.y ), math.floor( Vec.z ) )
end

-- Using a single ClientsideModel as it's far faster to draw it multiple times than creating one for every entity.
-- There's a few quirks to this, but they're not as important as the speed difference.

local KeepTexture	= CreateClientConVar( 'ErrorCleanse_KeepTexture', 0, true, false )
local KeepColor		= CreateClientConVar( 'ErrorCleanse_KeepColor', 1, true, false )
local DrawNoBounds	= CreateClientConVar( 'ErrorCleanse_DrawNoBounds', 1, true, false )

local function DrawError( self )
	if !self.ErrorCleanse then return end
	if !self.ErrorCleanse.Matrix then return end
	if !KeepTexture:GetBool() then render.MaterialOverride( 0 ) end
	if !KeepColor:GetBool() then render.SetBlend( 1 ); render.SetColorModulation( 1, 1, 1 ) end
	
		NewCube:SetRenderOrigin( self:LocalToWorld( self:OBBCenter() ) )
		NewCube:SetRenderAngles( self:GetAngles() )
		
		NewCube:EnableMatrix( 'RenderMultiply', self.ErrorCleanse.Matrix )

		NewCube:SetupBones()
		NewCube:DrawModel()
		
	NewCube:SetRenderOrigin()
	NewCube:SetRenderAngles()
end

-- This is hacky and should only be a temporary fix. I should be finding a better way to detect whether or not it's OK to replace.
local Blacklist = {}
Blacklist['class cluaeffect'] = true
Blacklist['viewmodel'] = true

local function ValidError( Ent )
	if !IsValid( Ent ) then return end
	if !Ent:GetTable() then return end
	if Ent:GetModel() != 'models/error.mdl' then return end
	
	if Blacklist[ Ent:GetClass():lower() ] then return end
	if Ent.Widget then return end
	
	if FloorVector(Ent:OBBMins()) == InvalidMins && FloorVector(Ent:OBBMaxs()) == InvalidMaxs then return end
	if Ent:GetPhysicsObjectCount() > 1 then return end -- This doesn't work well with ragdolls. :x
	--if Ent:BoundingRadius() == 0 then Ent:SetNoDraw( !DrawNoBounds:GetBool() ) return end
	
	return true
end

local function ApplyRenderOverride( Ent )
	if !ValidError( Ent ) then return end
	Ent.RenderOverride = DrawError
	--Ent.Draw = DrawError
	
	local NullScale = Matrix()
	NullScale:Scale( vector_origin )
	Ent:EnableMatrix( 'RenderMultiply', NullScale )
end

local function UnapplyErrorCleanse( Ent )
	if !IsValid( Ent ) then return end
	if !Ent.ErrorCleansed then return end
	
	Ent.RenderOverride = nil
	Ent:DisableMatrix( 'RenderMultiply' )
	
	Ent:DrawShadow( true ) -- Kinda shitty if the entity wasn't supposed to have shadows for some reason.
	
	if Ent.OldMins && Ent.OldMaxs then
		Ent:SetRenderBounds( Ent.OldMins, Ent.OldMaxs )
	end
	
	timer.Destroy( 'ErrorCleanse.RO.'..Ent:EntIndex() )
	timer.Destroy( 'ErrorCleanse.Apply.'..Ent:EntIndex() )
	
	Ent.ErrorCleansed = false
end

local function ApplyErrorCleanse()
	if !ValidError( Ent ) then
		UnapplyErrorCleanse( Ent )
		return
	end
	
	Ent.OldMins, Ent.OldMaxs = Ent:GetRenderBounds()
	
	local Mins = Ent:OBBMins()
	local Maxs = Ent:OBBMaxs()
	
	Ent.ErrorCleanse = {}
	Ent.ErrorCleanse.Matrix = Matrix()
	Ent.ErrorCleanse.Matrix:Scale( (Maxs - Mins)/2 )
	
	ApplyRenderOverride( Ent )
	
	Ent:DrawShadow( false )
	Ent:SetRenderBounds( Mins, Maxs )
	
	-- HACK: The propspawn effect sometimes replaces RenderOverride, so run it again!
	SafeRemoveEntity( Ent.SpawnEffect )
	timer.Create( 'ErrorCleanse.RO.'..Ent:EntIndex(), 0.5, 10, function() ApplyRenderOverride(Ent) end)
	
	Ent.ErrorCleansed = true
end

local function Spawned( Ent )
	if !ValidError( Ent ) then return end
	timer.Create( 'ErrorCleanse.Apply.'..Ent:EntIndex(), 5, 6, function()
		ApplyErrorCleanse( Ent )
	end)
end

local function ReInitialize()
	for K, Ent in pairs( ents.GetAll() ) do
		Spawned( Ent )
	end
end

local function ReplaceMissingMat() -- This was an expirement to replace the purple&black material.
	local NewError = Material( 'turtle/newmissing' )
	local ErrorTex = Material('turtle/random_error_this/is/not/real-')
	
	ErrorTex:SetMaterialTexture( '$basetexture', NewError:GetMaterialTexture( '$basetexture' ) )
end

-- Apply everything!

hook.Add( 'OnEntityCreated', 'ErrorCleanse.Spawned', Spawned )
hook.Add( 'InitPostEntity', 'ErrorCleanse.InitPostEntity', ReInitialize )

timer.Create( 'ErrorCleanse.AddErrors', 0.25, 0, ents.GetAll ) -- This fixes entities sometimes not getting OnEntityCreated called for them.
timer.Create( 'ErrorCleanse.ReInitialize', 15, 0, ReInitialize ) -- This shouldn't even be required -- but I feel I should include it incase something is missed first time.

concommand.Add( 'ErrorCleanse_ReInit', ReInitialize )
concommand.Add( 'ErrorCleanse_ReplaceMissingMat', ReplaceMissingMat )