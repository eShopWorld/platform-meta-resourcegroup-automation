
 param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$sub,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$envName
 )

function InsertStringIntoSplit {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [AllowEmptyCollection()]
        [System.Collections.Hashtable]
        $list,    

        
        [Parameter(Mandatory=$true, Position=1)]
        [string]
        $namePrefix,

        [Parameter(Mandatory=$true, Position=2)]
        [string]
        $token,

        [Parameter(Position=3)]
        [int]
        $maxLength=256
    )

    $index=0
    foreach ($itemKey in $list.Keys)
    {
        $item = $list.Item($itemKey)
        if ($itemKey -like "$($namePrefix)*")
        {
            $index++
        }

        if ($itemKey -like "$($namePrefix)*" -and ($item.Length+ $token.Length +1) -le $maxLength)
        {
            $item= $item+','+$token
            $list[$itemKey]=$item
            return
        }
    }
    $suffix= if ($index -eq 0) {""} else {"${$index+1}"}

    $list.Add("$($namePrefix)$($suffix)", $token)
}

function ExtractVariablesIntoList {
    Param (
        [Parameter(Mandatory=$true, Position=0)]
        [string]
        $envVarSuffix,    

        [Parameter(Mandatory=$true, Position=1)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[System.Tuple[string,bool]]]
        $list,   

        [Parameter(Mandatory=$true, Position=2)]
        [System.Object[]]
        $envVars,

        [Parameter(Mandatory=$false, Position=3)]
        [bool]
        $parseValue = $true
    )


    $envVars | ? Key -Match "^[a-zA-z]+(?=-$($envVarSuffix))" | % {
        if ($parseValue) { $bool= [System.Convert]::ToBoolean($_.Value)} else {$bool = $false}

        $list.Add((New-Object 'System.Tuple[string,bool]' -ArgumentList $Matches[0].ToLowerInvariant(),$bool))    
    }
}

#get vsts input
$envVariables = Get-ChildItem Env:
$domainObjects = New-Object 'System.Collections.Generic.List[System.Tuple[string,bool]]'

ExtractVariablesIntoList -envVarSuffix "DOMAIN" -envVars $envVariables -list $domainObjects

$tenantObjects = New-Object 'System.Collections.Generic.List[System.Tuple[string,bool]]'
ExtractVariablesIntoList -envVarSuffix "TENANT" -envVars $envVariables -list $tenantObjects -parseValue $false

#process domains
$secretTags = New-Object 'System.Collections.Hashtable'

while ($domainObjects.Count -ne 0 ) {
    $domainAtHead = $domainObjects.Item(0)
    $domainObjects.RemoveAt(0)
    $domainName = $domainAtHead.Item1
    $domainTenantedFlag = "F"
    if ($domainAtHead.Item2 -eq $true)
    {
        $domainTenantedFlag = "T"
    }
    
    InsertStringIntoSplit -list $secretTags -token "$($domainName):$($domainTenantedFlag)" -namePrefix "domain"
}

#process tenants
while ($tenantObjects.Count -ne 0 ) {
    $tenantAtHead = $tenantObjects.Item(0)
    $tenantObjects.RemoveAt(0)
    $tenantName = $tenantAtHead.Item1
    
    InsertStringIntoSplit -list $secretTags -token $tenantName -namePrefix "tenant"
}


#create/reset RG
Connect-AzAccount -Identity #use MSI
Select-AzSubscription -Subscription $sub
New-AzResourceGroup -Name "platform-$($envName)-meta" -Location WestEurope -Force -Tag $secretTags

