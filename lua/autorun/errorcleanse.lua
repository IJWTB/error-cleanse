if ( game.SinglePlayer() ) then
    return
end

if ( SERVER ) then

    AddCSLuaFile()
    
    resource.AddFile( "models/props/smallcubetrt.mdl" )
    resource.AddFile( "materials/turtle/errorcleanse_opaque.vmt" )
    resource.AddFile( "materials/turtle/errorcleanse_opaque.vtf" )
    resource.AddFile( "materials/turtle/newmissing.vmt" )
    resource.AddFile( "materials/turtle/newmissing.vtf" )
    
    return
end

--[[--------------------------------------------------------------------------
-- Localized Functions & Variables
--------------------------------------------------------------------------]]--

local IsValid = IsValid
local Vector = Vector
local math = math
local render = render

local function floorVector( vec )
    vec.x = math.floor( vec.x )
    vex.y = math.floor( vec.y )
    vec.z = math.floor( vec.z )
end

--[[--------------------------------------------------------------------------
-- Namespace Tables
--------------------------------------------------------------------------]]--

errorcleanse = errorcleanse or {}

--[[--------------------------------------------------------------------------
-- Namespace Functions
--------------------------------------------------------------------------]]--
function errorcleanse.Initialize()
    -- This is hacky and should only be a temporary fix. I should be finding a better way to detect whether or not it's OK to replace.
    errorcleanse.ClassBlacklist = {
        ["class cluaeffect"] = true,
        ["class c_baseflex"] = true,
        viewmodel            = true,
    }
    
    errorcleanse.ZeroMatix = Matrix()
    errorcleanse.ZeroMatix:Scale( Vector( 0, 0, 0 ) )
    
    errorcleanse.ReplacementEnt = errorcleanse.ReplacementEnt or ClientsideModel( "models/props/smallcubetrt.mdl", RENDERGROUP_BOTH )
    errorcleanse.ReplacementEnt:SetNoDraw( true )
    errorcleanse.ReplacementEnt:DrawShadow( false )
    errorcleanse.ReplacementEnt:DestroyShadow()
    
    -- When the server is also missing the content, it has no way of knowing the actual size of the model.
    -- Such cases (e.g. workshop dupes) can be identified if they use the following OBBS min/maxs.
    errorcleanse.InvalidMins = Vector( -8, -38,  0 ) 
    errorcleanse.InvalidMaxs = Vector(  9,  44, 67 )
    
    -- Using a single ClientsideModel as it's far faster to draw it multiple times than creating one for every entity.
    -- There's a few quirks to this, but they're not as important as the speed difference.
    errorcleanse.KeepTexture  = CreateClientConVar( "errorcleanse_keeptexture",  0, true, false )
    errorcleanse.KeepColor    = CreateClientConVar( "errorcleanse_keepcolor",    1, true, false )
    errorcleanse.DrawNoBounds = CreateClientConVar( "errorcleanse_drawnobounds", 1, true, false )
    
    --[[--------------------------------------------------------------------------
    -- DrawError( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.DrawError( ent )
        if not ent.ECMatrix then return end
        
        if not errorcleanse.KeepTexture:GetBool() then
            render.MaterialOverride( 0 )
        end
        
        if not errorcleanse.KeepColor:GetBool() then
            render.SetBlend( 1 )
            render.SetColorModulation( 1, 1, 1 )
        end
        
        errorcleanse.ReplacementEnt:SetRenderOrigin( ent:LocalToWorld( ent:OBBCenter() ) )
        errorcleanse.ReplacementEnt:SetRenderAngles( ent:GetAngles() )
        
        errorcleanse.ReplacementEnt:EnableMatrix( "RenderMultiply", ent.ECMatrix )
        errorcleanse.ReplacementEnt:SetupBones()
        
        errorcleanse.ReplacementEnt:DrawModel()
    end

    --[[--------------------------------------------------------------------------
    -- IsValidError( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.IsValidError( ent )
        if not IsValid( ent ) then return false end
        if not ent:GetTable() then return false end
        if ent:GetModel() ~= "models/error.mdl" then return false end
        
        if errorcleanse.ClassBlacklist[ ent:GetClass() ] then return false end
        if ent.Widget then return false end
        if ent:GetPhysicsObjectCount() > 1 then return false end -- This doesn't work well with ragdolls. :x

        -- Below seems to return and ignore content spawned in from workshop dupes that not even the server has,
        -- since then the client has no way of knowing the real model bounds and can't properly scale the matrix.
        -- I'd argue the replacement entity is still better to see than the default ERROR model, so it is commented.
        --if floorVector(ent:OBBMins()) == errorcleanse.InvalidMins && floorVector(ent:OBBMaxs()) == errorcleanse.InvalidMaxs then print("obbs") return end


        --if ent:BoundingRadius() == 0 then ent:SetNoDraw( not errorcleanse.DrawNoBounds:GetBool() ) return end
        
        return true
    end

    --[[--------------------------------------------------------------------------
    -- Hook::OnEntityCreated( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.OnEntityCreated( ent )
        errorcleanse.Apply( ent )
    end
    hook.Add( "OnEntityCreated", "ErrorCleanse.OnEntityCreated", errorcleanse.OnEntityCreated )

    --[[--------------------------------------------------------------------------
    -- Apply( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.Apply( ent )
        if not errorcleanse.IsValidError( ent ) then
            errorcleanse.Remove( ent )
            return
        end
        
        ent.ECOriginalMins, ent.ECOriginalMaxs = ent:GetRenderBounds()
        
        local mins = ent:OBBMins()
        local maxs = ent:OBBMaxs()
        
        ent.ECMatrix = Matrix()
        ent.ECMatrix:Scale( (maxs - mins) / 2 )
        
        ent:DrawShadow( false )
        ent:DestroyShadow()
        
        errorcleanse.ApplyRenderOverride( ent )
        
        ent:SetRenderBounds( mins, maxs )
        
        -- HACK: The propspawn effect sometimes replaces RenderOverride, so run it again!
        --SafeRemoveEntity( ent.SpawnEffect )
        --[[timer.Create( "ErrorCleanse.RenderOverride."..ent:EntIndex(), 0.5, 10, function()
            errorcleanse.ApplyRenderOverride(ent)
        end )]]
        
        ent.ErrorCleansed = true
    end

    --[[--------------------------------------------------------------------------
    -- ApplyRenderOverride( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.ApplyRenderOverride( ent )
        ent.RenderOverride = errorcleanse.DrawError
        ent:EnableMatrix( "RenderMultiply", errorcleanse.ZeroMatix )
    end

    --[[--------------------------------------------------------------------------
    -- Remove( entity )
    --------------------------------------------------------------------------]]--
    function errorcleanse.Remove( ent )
        if not IsValid( ent )    then return end
        if not ent.ErrorCleansed then return end
        
        ent.RenderOverride = nil
        ent:DisableMatrix( "RenderMultiply" )
        
        ent:DrawShadow( true )
        
        if ent.ECOriginalMins and ent.ECOriginalMaxs then
            ent:SetRenderBounds( ent.ECOriginalMins, ent.ECOriginalMaxs )
        end
        
        ent.ErrorCleansed = nil
    end

    --[[--------------------------------------------------------------------------
    -- ReplaceMaterial
    --------------------------------------------------------------------------]]--
    function errorcleanse.ReplaceMaterial()
        -- This was an experiment to replace the purple&black material.
        local replacementTexture   = Material( "turtle/newmissing" )
        local originalErrorTexture = Material( "turtle/random_error_this/is/not/real-" )
        
        originalErrorTexture:SetTexture( "$basetexture", replacementTexture:GetTexture( "$basetexture" ) )
    end
    concommand.Add( "errorcleanse_replace_missing_material", errorcleanse.ReplaceMaterial )

    --[[--------------------------------------------------------------------------
    -- Reinitialize
    --------------------------------------------------------------------------]]--
    function errorcleanse.Reinitialize()
        for _, ent in ipairs( ents.GetAll() ) do
            errorcleanse.OnEntityCreated( ent )
        end
    end
    hook.Add( "InitPostEntity", "ErrorCleanse.InitPostEntity", Reinitialize )
    concommand.Add( "errorcleanse_reinitialize", errorcleanse.Reinitialize )

    timer.Create( "ErrorCleanse.AddErrors", 1, 0, ents.GetAll ) -- This fixes entities sometimes not getting OnEntityCreated called for them.
end
hook.Add( "InitPostEntity", "errorcleanse.initialize", errorcleanse.Initialize )