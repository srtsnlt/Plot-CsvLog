using namespace System
using namespace System.Collections.Generic

$conf = Get-Content "$($PSCommandPath).conf.jsonc" -Raw |
ConvertFrom-Json

$inDatas = Get-Content $conf.InFileName |
ConvertFrom-Csv
$plotEnd = [TimeSpan]$conf.PlotEnd
$plotSpan = [TimeSpan]$conf.PlotSpan
$outFileName = "$($PSCommandPath).out.csv"

$outDatas = @()
$rounds = [Math]::Ceiling($plotEnd.TotalMilliseconds / $plotSpan.TotalMilliseconds)

$dataIndex = 0
$dataReadEnd = $false
$nameCallStack = [Stack[string]]::new()
$null = $nameCallStack.Push([Regex]::Replace( $inDatas[0].($conf.NameColumnName), $conf.NameReplaceRegexFrom, $conf.NameReplaceRegexTo ))
$nameTimes = [List[PSCustomObject]]::new()


switch
(
    1..$rounds
)
{default{
    $curSpanStart = $plotSpan.Multiply($_ -1)
    $curSpanEnd = $plotSpan.Multiply($_)

    if
    (
        $dataReadEnd
    )
    {
        # output cur span
        $outDatas += [PSCustomObject]@{
            StartTime = $curSpanStart.ToString('hh\:mm\:ss\.fff')
            EndTime = $curSpanEnd.ToString('hh\:mm\:ss\.fff')
            Name = $null
        }
        continue
    }

    $dataRecordTime = $null
    $dataRecordState = $null
    $dataRecordName = $null

    # seek out to cur data end
    while
    (
        $dataIndex -lt $inDatas.Count -1
    )
    {
        $null = $dataIndex ++

        # read cur data
        # data records
        $dataRecordPrev = $inDatas[$dataIndex -1]
        $dataRecordPrevTime = [TimeSpan]::ParseExact( $dataRecordPrev.($conf.TimeColumnName), $conf.TimeFormat, [cultureinfo]::InvariantCulture)

        $dataRecord = $inDatas[$dataIndex]
        $dataRecordTime =     [TimeSpan]::ParseExact( $dataRecord.($conf.TimeColumnName),     $conf.TimeFormat, [cultureinfo]::InvariantCulture)
        $dataRecordState = $dataRecord.($conf.StateColumnName)
        $dataRecordName = [Regex]::Replace( $inDatas[$dataIndex].($conf.NameColumnName), $conf.NameReplaceRegexFrom, $conf.NameReplaceRegexTo )

        # cur name
        $name = $nameCallStack.Pop()
        $null = $nameCallStack.Push($name)

        # data time in cur span
        $dataTime =
        (
            $curSpanEnd -lt $dataRecordTime ? $curSpanEnd : $dataRecordTime
        ).Subtract(
            $curSpanStart -gt $dataRecordPrevTime ? $curSpanStart : $dataRecordPrevTime
        )

        # name time
        $null = $nameTimes.Add([PSCustomObject]@{
            Name = $name
            Value = [decimal]$dataTime.TotalMilliseconds
        })

        # prepare for next data
        # name stack
        if
        (
            [Regex]::Match( $dataRecordState, $conf.StateRegexStart)
        )
        {
            $null = $nameCallStack.Push($dataRecordName)
        }
        elseif
        (
            [Regex]::Match($dataRecordState , $conf.StateRegexEnd)
        )
        {
            $null = $nameCallStack.Pop()
        }

        if
        (
            $dataRecordTime -ge $curSpanEnd
        )
        {
            break
        }
    }

    # output cur span
    $topNameGroup = @($nameTimes |
        Group-Object -Property Name |
        Sort-Object {
            ($_.Group | Measure-Object -Property Value -Sum).Sum
        } -Descending
    )[0]

    $outDatas += [PSCustomObject]@{
        StartTime = $curSpanStart.ToString('hh\:mm\:ss\.fff')
        EndTime = $curSpanEnd.ToString('hh\:mm\:ss\.fff')
        Name = $topNameGroup.Name
    }


    # clear name times
    $null = $nameTimes.Clear()

    # check read end
    if
    (
        $dataIndex -ge $inDatas.Count -1 -and
        $dataRecordTime -le $curSpanEnd
    )
    {
        $dataReadEnd = $true
        continue
    }
    
    # fall back 1 record
    # name stack
    if
    (
        [Regex]::Match( $dataRecordState, $conf.StateRegexStart)
    )
    {
        $null = $nameCallStack.Pop()
    }
    elseif
    (
        [Regex]::Match( $dataRecordState, $conf.StateRegexEnd)
    )
    {
        $null = $nameCallStack.Push($dataRecordName)
    }

    # data index
    $null = $dataIndex --
}}

$outDatas |
Export-Csv -Path $outFileName -NoTypeInformation
