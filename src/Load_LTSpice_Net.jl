using DataFrames

"""
This function takes in a file path/name and exports a dataframe consisting of the circuit parameters
Specifically the file should be from LTSPICE (or it wont work)

If no input is given, the user will be prompted for a FileName
"""
function LTSpiceLoad(FileName=nothing)
        # if FileName===nothing
        #         FileName = open_dialog("Pick a file")
        # end
        f =open(FileName)
         Lines =  readlines(f)

         close(f)
        KCount = 0
         SPICE_DF = DataFrame((Type = Any[], Value=Any[], Node1=Any[], Node2=Any[], Name=Any[],ESR = Any[],KCount = Any[],Attr1 = Any[],Attr2 = Any[],Attr3 = Any[],Node3 = Any[],Node4 = Any[]))
        for i in 1:length(Lines)

                Spaces = vcat(findall(" ",Lines[i])...)
                
                if ~(Lines[i][1]=='*')
                        # println(Lines[i])
                end
                if (Lines[i][1]=='R')|(Lines[i][1]=='L')|(Lines[i][1]=='C')
                        if length(Spaces)==3
                                Value = Lines[i][Spaces[3]+1:end]
                        else
                                Value = Lines[i][Spaces[3]+1:Spaces[4]-1]
                        end
                        Node1 = Lines[i][Spaces[1]+1:Spaces[2]-1]
                        Node2 = Lines[i][Spaces[2]+1:Spaces[3]-1]
                        Name = Lines[i][1:Spaces[1]-1]
                        RSerInds = findall("Rser=", Lines[i])
                        if length(RSerInds)>0
                                RSerIndEnd =RSerInds[1][end]+1
                                if RSerInds[1][end]>maximum(Spaces)
                                        RSerVal = MakeNumericalVals(Lines[i][RSerIndEnd:end])
                                else
                                        Tmp = findfirst(x-> x>RSerIndEnd,Spaces)
                                        RSerVal = MakeNumericalVals(Lines[i][RSerIndEnd:Spaces[Tmp]])
                                end
                        else
                                RSerVal=0
                        end
                        IsNoiseless = !(isempty(findall("noiseless", Lines[i])))

                        RParInds = findall("Rpar=", Lines[i])
                        if length(RParInds)>0
                                RParIndEnd =RParInds[1][end]+1
                                if RParInds[1][end]>maximum(Spaces)
                                        RParVal = MakeNumericalVals(Lines[i][RParIndEnd:end])
                                else
                                        Tmp = findfirst(x-> x>RParIndEnd,Spaces)
                                        RParVal = MakeNumericalVals(Lines[i][RParIndEnd:Spaces[Tmp]])
                                end
                        push!(SPICE_DF,['R' RParVal Node1 Node2 "RP"*Name 0.0 NaN NaN NaN NaN NaN NaN])
                        end

                        
                        if (Lines[i][1]=='R')&IsNoiseless
                                push!(SPICE_DF,[Lines[i][1] MakeNumericalVals(Value) Node1 Node2 Name RSerVal NaN "noiseless" NaN NaN NaN NaN])
                        else
                                push!(SPICE_DF,[Lines[i][1] MakeNumericalVals(Value) Node1 Node2 Name RSerVal NaN NaN NaN NaN NaN NaN])
                        end

                elseif (Lines[i][1]=='V')
                        Node1 = Lines[i][Spaces[1]+1:Spaces[2]-1]
                        Node2 = Lines[i][Spaces[2]+1:Spaces[3]-1]
                        Name = Lines[i][1:Spaces[1]-1]
                        push!(SPICE_DF,[Lines[i][1] 1 Node1 Node2 Name 0 NaN NaN NaN NaN NaN NaN])
                elseif (Lines[i][1]=='K')
                        KCount+=1
                        L1Name = Lines[i][Spaces[1]+1:Spaces[2]-1]
                        L1Row = findfirst(L1Name.==SPICE_DF[:,5])

                        
                        
                        L2Name = Lines[i][Spaces[2]+1:Spaces[3]-1]
                        L2Row = findfirst(L2Name.==SPICE_DF[:,5])

                        if !(L1Row===nothing || L2Row===nothing)

                                L1Val = SPICE_DF[L1Row,2]
                                L2Val = SPICE_DF[L2Row,2]
                                
                                CouplingCoeff = MakeNumericalVals(Lines[i][Spaces[3]+1:end])
                                Name = Lines[i][1:Spaces[1]-1]
                                # println(typeof(L1Row))
                                SPICE_DF[L1Row,7] = KCount
                                SPICE_DF[L1Row,8] = L2Row
                                KCount+=1

                                SPICE_DF[L2Row,7] = KCount
                                SPICE_DF[L2Row,8] = L1Row
                                SPICE_DF[L1Row,9] = CouplingCoeff
                                SPICE_DF[L2Row,9] = CouplingCoeff
                                SPICE_DF[L1Row,10] = L2Val
                                SPICE_DF[L2Row,10] = L1Val
                        end
                       
                elseif (Lines[i][1]=='X' || Lines[i][1]=='G') # This is for either standard opamps or voltage controlled current sources in LTSPICE.
                        
                        if (Lines[i][Spaces[4]+1:Spaces[5]-1]=="opamp")
                                # KCount+=1
                                Node1 = Lines[i][Spaces[1]+1:Spaces[2]-1]
                                Node2 = Lines[i][Spaces[2]+1:Spaces[3]-1]
                                Node3 = Lines[i][Spaces[3]+1:Spaces[4]-1]
                                Node4 = "0"
                                Name = Lines[i][1:Spaces[1]-1]
                                GBW = GetSPICEAttr("GBW",Lines[i],Spaces)
                                
                                Gain = GetSPICEAttr("Aol",Lines[i],Spaces)
                                # print(Gain)
                                push!(SPICE_DF,['G' Gain Node1 Node2 Name 0.0 NaN NaN NaN GBW Node3 Node4])
                                push!(SPICE_DF,['R' 1 Node3 Node4 "RP"*Name 0.0 NaN NaN NaN NaN NaN NaN])
                                push!(SPICE_DF,['C' Gain/GBW/(2*pi) Node3 Node4 "CP"*Name 0.0 NaN NaN NaN NaN NaN NaN])
                        
                        elseif (Lines[i][1]=='G')
                                # KCount+=1
                                Node3 = Lines[i][Spaces[1]+1:Spaces[2]-1]
                                Node4 = Lines[i][Spaces[2]+1:Spaces[3]-1]
                                Node1 = Lines[i][Spaces[3]+1:Spaces[4]-1]
                                Node2 = Lines[i][Spaces[4]+1:Spaces[5]-1]
                                Name = Lines[i][1:Spaces[1]-1]
                                GBW = GetSPICEAttr("GBW",Lines[i],Spaces)
                                
                                Gain  = MakeNumericalVals(Lines[i][Spaces[5]+1:end])
                                # print(Gain)
                                push!(SPICE_DF,['G' Gain Node1 Node2 Name 0.0 NaN NaN NaN 1e9 Node3 Node4])
                                
                        end
                end


        end

        return SPICE_DF
end


"""
A simple string to numeric conversion for metric prefixes
Input: String 
Output Float64

e.g. 
        MakeNumericalVals("1n")
         > 1.0e-9
        MakeNumericalVals.(["1n" , "2m"])
                2-element Array{Float64,1}:
                1.0e-9
                0.002
"""
function MakeNumericalVals(ValString::String)
        NewString = replace(ValString,"Meg"=>"e6")
        NewString = replace(NewString,"k"=>"e3")
        NewString = replace(NewString,"K"=>"e3")
        NewString = replace(NewString,"m"=>"e-3")
        NewString = replace(NewString,"u"=>"e-6")
        NewString = replace(NewString, "n"=>"e-9")
        NewString = replace(NewString, "p"=>"e-12")
        return parse(Float64,NewString)
end

function GetSPICEAttr(NameString::String,Line,Spaces,DefaultVal=0.0)
        AttrInds = findall(NameString * "=", Line)
        Value = DefaultVal
        if length(AttrInds) > 0
                AttrIndEnd = AttrInds[1][end] + 1
                if AttrInds[1][end] > maximum(Spaces)
                        Value = MakeNumericalVals(Line[AttrIndEnd:end])
                else
                        Tmp = findfirst(x -> x > AttrIndEnd, Spaces)
                        Value = MakeNumericalVals(Line[AttrIndEnd:Spaces[Tmp]])
                end

        end
        return Value
end