
abstract type Toroid end

struct DCore <: Toroid

    FlatHeight::Float64
    MaxHeight::Float64 #Height from CENTER LINE, so the actual core is 2 times as tall overall. This is the half-height effectively
    RadiusAtPeak::Float64 #This is how far from the center axis the peak of the geometry is, not the radius of curvature at the apex
    ID::Float64 #Thner diameter of the core
    OD::Float64 #Thner diameter of the core
    Turns::Int64
    Layers::Int64
    WireLength::Float64
    Resistance::Float64
end

struct Circle <: Toroid

    CoreRadius::Float64
    CenterRadius::Float64
    ID::Float64 #Thner diameter of the core
    OD::Float64 #Thner diameter of the core
    Turns::Int64
    Layers::Int64
    WireLength::Float64
    Resistance::Float64
end
struct GeneralParams <: Toroid
    SingleLayerInductance::Float64
    WireDiameter::Float64
    TargetInductance::Float64

end

mutable struct Geom
    DCore::DCore
    Circ::Circle
    General::GeneralParams
end
"""
This function makes an optimal D-Core toroid given the following inputs:
    Dia - wire diamter in meters
    LTarget-  target inductance in Henries

    kwarg:
    NumLayers - Number of windings layers
    CoreMu - permeability scaling factor
    Alpha - ratio of OD/ID use an integer between 2-5
    CuFillFactor - scales resistance value. If using litz it will be <1
    ExportFileName - if you want to export the SVG and text file of the core cross section you can use this. If you enter a file name E.g. "Test", it will save two files in the present working directory as: "ToroidParameters-Test.txt"and "DCoreGeom-Test.SVG"
    NPts - number of points in the exported svg

"""
function ToroidOptimizer(
    Dia,
    LTarget;
    NumLayers = 2,
    CoreMu = 1,
    Alpha = 2,
    CuFillFactor = 1,
    ExportFileName = nothing,
    NPts = 100
)
    ## Summary: To use this function enter the wire diameter and the target
    #inductance (in meters and Henries). The calculations assume "NumLayers" fully
    #wound layers as it is a good balance between heat dissipation and
    #geometric efficiency (2 is a good option, unless heat is an issue). The output is a struct containing the geometric
    #information for a toroid with a D shaped core, and a circular core.


    ## Constants
    μ_o = 4 * pi * 10^(-7)
    μ = μ_o * CoreMu
    L0 = μ * Dia / (2 * pi)
    L = LTarget / NumLayers^2 #Use the assumption that there will be 'NumLayers' fully wound layers...
    #If there are two fully wound layers, it can be calculated at just one
    #layer with 1/4 the inductance. Then double it when winding
    LperL0 = L / L0 #An intermediate dimensionless parameter that comes from the papers which these formulas are derived.
    SingleLayerInductance = L
    WireDiameter = Dia
    TargetInductance = LTarget
    General =
        GeneralParams(SingleLayerInductance, WireDiameter, TargetInductance)

    ## D shaped core
    #Alpha = 2; #User can change this to an integer between 2 and 5 (inclusive) varies the aspect ratio of the D
    #A high alpha value such as 5 will be a taller/bigger core with fewer
    #turns. It is theoretically more efficient but will probably have more
    #leakage flux.

    # AlphaMat Key. The columns represent [alpha e h p s t]

    AlphaMat = [
        2 0.26 0.645 3.6 0.72 1.77
        3 0.85 1.5 8.0 2.74 4.42
        4 1.6 2.4 12.8 5.76 8.09
        5 2.45 3.4 17.9 9.61 12.6
    ] #Table 1 From  "D-Shaped toroidal cage inductors" P.N. Murgatroyd & D. Belahrache,1989

    T = AlphaMat[Alpha-1, 6] #Picking a value in the table for clarity
    S = AlphaMat[Alpha-1, 5] #Also Selecting value for clarity
    P = AlphaMat[Alpha-1, 4] # As above

    KFunk_D(k) =
        abs.((2 * pi)^0.5 * (S / (P^(3 / 2))) * k .^ (3 / 2) + 0.25 * k - LperL0) #From "The Optimal Form for Coreless Inductor", P. Murgatroyd IEEE TMI, 25 No. 3 1989
    Ktmp = optimize(KFunk_D, 0, 1e5) #solving for ideal K with bisection method
    K = Ktmp.minimizer
    WireLength_D = K * Dia #Equation 6 in "Economic designs for..."
    Turns_D = (2 * pi * K / P)^(1 / 2) # Also from P. Murgatroyd, section 4, Eq. 20 in "Economic designs for single-layer toroidal inductors"
    # TurnsD = sqrt(2*pi*L/(T*μ*B)); #Turns needed in a D shaped core toroid
    # ID_DToroid = 2*B;
    # B = WireLength_D/(Turns_D*P); #B=inner radius, so B = total length/(number of turns*Perimeter of each turn)
    B = Dia / 2 + Turns_D * Dia / (2 * pi) #Making it so that the wires all touch on the inner edge of the core
    
    if NumLayers>1
        IDVec = MultiLayerToroid_ID_Calc(NumLayers,B*2,Dia)[end] #Updating the ID so that the innermost layer have all wires densely packed
    else
        IDVec = B*2
    end

    ## For the following reference Fig 4 in "D-Shaped toroidal cage inductors" P.N. Murgatroyd & D. Belahrache,1989
    FlatHeight = B * AlphaMat[Alpha-1, 2]
    MaxHeight = B * AlphaMat[Alpha-1, 3] #Height from CENTER LINE, so the actual core is 2 times as tall overall. This is the half-height effectively
    RadiusAtPeak = Alpha^0.5 * B #This is how far from the center axis the peak of the geometry is, not the radius of curvature at the apex
    ID = B * 2#Thner diameter of the core
    OD = 2 * Alpha * B
    Turns = round(Turns_D * NumLayers)
    Layers = NumLayers
    WireLength = WireLength_D * NumLayers
    D_WireR = Length2Resist(WireLength, Dia; FillFac = CuFillFactor)
    DCoreGeom = DCore(
        FlatHeight,
        MaxHeight,
        RadiusAtPeak,
        IDVec[end], #using the new ID that accounts for the windings piling together on the inner surface
        OD,
        round(Turns),
        Layers,
        WireLength,
        D_WireR,
    )

    ## circular core


    KFunk(k) = abs.(0.2722 * k .^ (3 / 2) + 0.25 * k - LperL0) #From "The Optimal Form for Coreless Inductor", P. Murgatroyd IEEE TMI, 25 No. 3 1989
    Kopt = optimize(KFunk, 0, 1e5) #solving for ideal K 
    K = Kopt.minimizer
    WireLength = K * Dia
    Turns = 0.8165 * K^(1 / 2) # Also from P. Murgatroyd, section 2 in "Economic designs for single-layer toroidal inductors"
    R = WireLength / (2 * pi * Turns)# Equation 2 in "Economic designs for single-layer toroidal inductors",P. Murgatroyd
    T = Dia / (sin(pi / Turns) * 2) + R# Equation 3 in "Economic designs for single-layer toroidal inductors"

    Turns = Turns * NumLayers
    WireLength = WireLength * NumLayers
    Layers = NumLayers
    ID = 2 * (T - R)
    OD = 2 * (T + R)
    CoreRadius = R
    CenterRadius = T
    Circ_WireR = Length2Resist(WireLength, Dia; FillFac = CuFillFactor)
    CircleGeom = Circle(
        CoreRadius,
        CenterRadius,
        ID,
        OD,
        round(Turns),
        Layers,
        WireLength,
        Circ_WireR,
    )


    ## Back-checking the work with two approximations.

    Approx_EnclosedArea_DCore =
        DCoreGeom.MaxHeight * 2 * (DCoreGeom.OD - DCoreGeom.ID) / 2 * 0.75#This ROUGH approximation is assuming the core fills 75# of the circumscribed rectangle around the core (roughly a semi-cirle)
    SanityCheckInductance =
        μ * DCoreGeom.Turns^2 * Approx_EnclosedArea_DCore /
        (pi * (DCoreGeom.OD + DCoreGeom.ID) / 2)



    MeanPathLength = (DCoreGeom.OD + DCoreGeom.ID) * pi



    Laa = μ * CircleGeom.Turns^2 * R^2 / (2 * T)#Another formula for inductance of circular toroid
    # 
    # println("Target inductance is: $(round(LTarget*1e6)) μH")
    # println(
    #     "Sanity check inductance is: $(round(SanityCheckInductance*1e6)) μH",
    # )
    # println("
    # FlatHeight     :$(round(DCoreGeom.FlatHeight*1000;sigdigits=2)) mm
    # MaxHeight      :$(round(DCoreGeom.MaxHeight*1000;sigdigits=2)) mm
    # RadiusAtPeak   :$(round(DCoreGeom.RadiusAtPeak*1000;sigdigits=2)) mm
    # ID             :$(round(DCoreGeom.ID*1000;sigdigits=2)) mm
    # OD             :$(round(DCoreGeom.OD*1000;sigdigits=2)) mm
    # Turns          :$(DCoreGeom.Turns) Turns
    # Layers         :$(DCoreGeom.Layers) Turns
    # WireLength     :$(round(DCoreGeom.WireLength;sigdigits=2)) meters
    # WireResist     :$(round(DCoreGeom.Resistance;sigdigits=2)) Ω")
    CoilGeom = Geom(DCoreGeom, CircleGeom, General)

    if ~(ExportFileName===nothing)
        DCoreParams2SVG(DCoreGeom.ID*1000 , DCoreGeom.OD*1000,"DCoreGeom-"*ExportFileName*".SVG";NPts = NPts)
        WriteToroidParamsTextFile(DCoreGeom, CircleGeom, General,"ToroidParameters-"*ExportFileName*".txt")
    end
    return CoilGeom
end



function Length2Resist(L, Diam; ρ = 1.68e-8, FillFac = 1)
    if Diam > 0.1
        println(
            "Diameter must be in METERS, it was automatically multiplied by 1e-3 in case you entered it in mm",
        )
        Diam = Diam * 1e-3
    end
    A = pi / 4 .* Diam .^ 2
    return L * ρ / FillFac / A
end

"""
This function takes in an inner and outer radius and makes the ideal "D-shaped" toroid core

It returns a list of coordinates (r,z) where r is the radial location
on the toroid, and z is the height from the center axis. In a cross-section
view this is essentially x and y.


r₁ - inner radius
r₂ - outer radius
dr (kwarg) is the dr between each sampled location


"""
function DCoreGeom(r₁, r₂; dr = 0.0001,NPts = nothing,PlotOn=false,UpsamplePoints = 1e4)
    dZdr(r) = log.(sqrt(r₁ * r₂) ./ r) ./ sqrt.(log.(r ./ r₁) .* log.(r₂ ./ r))
    if ~(NPts===nothing)
        dr = (r₂ - r₁) / UpsamplePoints
    end
    rᵢ = r₁ + dr / 10#starting at a small fraction above zero, to avoid an inf.
    r = [rᵢ]
    zᵢ = 0.0
    z = [zᵢ] # initializing vector
    II = 1 #iterator
    NumIters = floor((r₂ - r₁) / dr)

    while (NumIters > II)
        dz = dZdr(rᵢ)
        zᵢ +=dz*dr
        rᵢ += dr

        push!(z, zᵢ)
        push!(r, rᵢ)
        II += 1
    end
    z .-= z[end] #the boundary condition at the end must be fixed to equal 0
    
    z[1] = 0 #because of the inf initial dz/dr, the initial boundary must be manually set to zero
    ZFlatHeight = z[2]
    StartPts = Int(ceil(ZFlatHeight/dr))
    for i in 1:StartPts
        insert!(z,1+i,z[1+i]*i/StartPts)
        insert!(r,1+i,r[1])
    end

    z = vcat(z[:],-1 .*reverse(z[2:end-2]))
    r = vcat(r[:],reverse(r[2:end-2]))
    DownsampleIndex = 1:Int(round(UpsamplePoints/NPts)):length(z)
    z = z[DownsampleIndex]
    r = r[DownsampleIndex]
    if PlotOn
        plot(r, z)
    end
    return r, z
end




"""
This function takes in the parameters of a circular Rogowski coil
    N: Num turns,
    ID: ID of circle in meters
    OD: OD of circle in meters
    and kwargs:
    Current: Current in the wire being sensed
    μ: permeability of the material
    ω: frequency (rad/sec) of current
"""
function Rogowski_Calc(N,ID,OD;Current=1,μ=4*π*1e-7,ω = 25e3*2*π)

    M₂₁ =μ*N/2*(ID+OD-2*√(ID*OD)) #From multiple sources. 

    V = ω*M₂₁*Current
    return (M₂₁,V)
end


"""
This function takes in the parameters of a rectagular Rogowski coil
    N: Num turns,
    h: height of rectangle in meters
    ID: ID of rectangle in meters
    OD: OD of rectangle in meters
    and kwargs:
    Current: Current in the wire being sensed
    μ: permeability of the material
    ω: frequency (rad/sec) of current
"""
function Rogowski_Calc(N,h,ID,OD;Current=1,μ=4*π*1e-7,ω = 25e3*2*π)
    
    
    M₂₁ =μ*N/(2*π)*h*(log(OD/ID)) #From multiple sources. 

    V = ω*M₂₁*Current
    return (M₂₁,V)
end

function DCore_DetermineIdealInduct(ID,N,α)
    #Equation 7
     # AlphaMat Key. The columns represent [alpha e h p s t]
     μ₀ = 4*pi*1e-7
     AlphaMat = [
        2 0.26  0.645 3.6   0.72  1.77
        3 0.85  1.5   8.0   2.74  4.42
        4 1.6   2.4   12.8  5.76  8.09
        5 2.45  3.4   17.9  9.61  12.6
        6 3.4   4.5   23.3  14.2  17.8
        7 4.4   5.6   28.9  19.4  23.7
    ] #Table 1 From  "D-Shaped toroidal cage inductors" P.N. Murgatroyd & D. Belahrache,1989

    T = AlphaMat[α-1, 6] #Picking a value in the table for clarity
    S = AlphaMat[α-1, 5] #Also Selecting value for clarity
    #S₁ = AlphaMat[α, 5] #Also Selecting value for clarity
    P = AlphaMat[α-1, 4] # As above
    E = AlphaMat[α-1, 2] # As above
    B = ID/2 #For consistency with the paper
    #L = μ₀*N^2*B / (2*π)*((2*E+1)/4 + 2/3*S + S₁)
    println(T)
    L = T * μ₀*N^2*B / (2*π)
    return L
end

function CircCore_DetermineIdealInduct(IRad,N,α)
    IRad = IRad*100
    ORad = IRad*α
    R = (ORad+IRad)/2
    a = (ORad-IRad)/2
    return 1e-6*(0.01257*N^2*(R-√*(R^2-a^2)))
end

function MultiLayerToroid_ID_Calc(Layers,ID,WireDia)

  
    IRad = ID/2
    Φ = asin(WireDia/(2*IRad))
    
    IRadVec = zeros(Layers,1)
    IRadVec[1] = IRad

    for i in 2:Layers
        IRadVec[i] = IRadVec[i-1] * cos(Φ) + sqrt(WireDia^2 - IRadVec[i-1]^2 * sin(Φ)^2)
    end

    return IRadVec*2

end