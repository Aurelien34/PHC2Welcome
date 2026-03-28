param (
    [Parameter(Mandatory=$true)]
    [string]$InputPath,
    [Parameter(Mandatory=$true)]
    [string]$OutputPath
)

write-host "Processing : $InputPath..."

# Read WAV file
$bytes = [System.IO.File]::ReadAllBytes($InputPath)

# Skip 44 bytes as it is easier that way :)
$dataOffset = 44
$lastIndex = $bytes.Length - 1

# Ignore last byte if it is 0
if ($lastIndex -ge $dataOffset -and $bytes[$lastIndex] -eq 0) {
    $lastIndex--
}

[byte[]]$audioData = $bytes[$dataOffset..$lastIndex]

# --- 1. Compute the 46-state Lookup ---
$ay_vol = @(0, 8, 11, 15, 22, 32, 43, 61, 86, 119, 169, 233, 324, 460, 646, 1000)

$validStates = New-Object System.Collections.ArrayList
for ($i = 0; $i -lt 16; $i++) {
    [void]$validStates.Add(@($i, $i, $i))
    if ($i -lt 15) {
        $j = [int]$i + 1
        [void]$validStates.Add(@($j, $i, $i))
        [void]$validStates.Add(@($j, $j, $i))
    }
}

$target_max = $ay_vol[15] * 3

# Pre-calculate 0-255 ideal target index (0-45)
[byte[]]$targetToIndex = New-Object byte[] 256
for ($i = 0; $i -lt 256; $i++) {
    $target = ($i / 255.0) * $target_max
    
    $best_index = 0
    $best_diff = 9999999
    
    for ($idx = 0; $idx -lt $validStates.Count; $idx++) {
        $state = $validStates[$idx]
        $a = $state[0]
        $b = $state[1]
        $c = $state[2]
        $s = $ay_vol[$a] + $ay_vol[$b] + $ay_vol[$c]
        $diff = [Math]::Abs($s - $target)
        if ($diff -lt $best_diff) {
            $best_diff = $diff
            $best_index = $idx
        }
    }
    $targetToIndex[$i] = [byte]$best_index
}

# --- 2. ROBUST NORMALIZATION ---
# Find percentiles to ignore anecdotal outliers (e.g. sporadic 0s)
$sorted = $audioData | Sort-Object
$p005_idx = [math]::Floor($sorted.Length * 0.005)
$p995_idx = [math]::Floor($sorted.Length * 0.995)

$min_val = $sorted[$p005_idx]
$max_val = $sorted[$p995_idx]

if ($max_val -eq $min_val) {
    $max_val += 1
}

# 128 is the silence center. Find maximum valid deviation
$dev_min = 128 - $min_val
$dev_max = $max_val - 128
$max_dev = [math]::Max($dev_min, $dev_max)

if ($max_dev -eq 0) {
    $max_dev = 1
}

# Factor needed to stretch $max_dev to 127
$scale = 127.0 / $max_dev

# Modify the array safely in memory
for ($i = 0; $i -lt $audioData.Length; $i++) {
    $val = $audioData[$i] - 128
    $scaled = $val * $scale
    $new_val = 128 + [math]::Round($scaled)
    # Hard clip edges to prevent overflows
    if ($new_val -lt 0) { $new_val = 0 }
    if ($new_val -gt 255) { $new_val = 255 }
    
    # Convert physically stretched 8-bit dynamic value into actual AY 46-stage optimal matrix index mapping
    $audioData[$i] = $targetToIndex[[int]$new_val]
}

# Add Fadein/out to suppress pop sounds
$first = $audioData[0]
$last = $audioData[-1]
[byte[]]$fadeIn = @(
    [byte]0,
    [byte]([math]::Floor($first * 0.25)),
    [byte]([math]::Floor($first * 0.50)),
    [byte]([math]::Floor($first * 0.75)),
    [byte]([math]::Floor($first * 0.90))
)
[byte[]]$fadeOut = @(
    [byte]([math]::Floor($last * 0.90)),
    [byte]([math]::Floor($last * 0.75)),
    [byte]([math]::Floor($last * 0.50)),
    [byte]([math]::Floor($last * 0.25)),
    [byte]0
)
$audioData = $fadeIn + $audioData + $fadeOut

# 8 to 6 bits packing
# Pack the 0-45 indices (6 bits) densely into 3 bytes per 4 samples
$paddedLens = [math]::Ceiling($audioData.Length / 4.0) * 4
$packedLen = ($paddedLens / 4) * 3
[byte[]]$packedData = New-Object byte[] $packedLen

$outIdx = 0
for ($i = 0; $i -lt $audioData.Length; $i += 4) {
    $s0 = $audioData[$i]
    $s1 = if (($i + 1) -lt $audioData.Length) { $audioData[$i + 1] } else { 0 }
    $s2 = if (($i + 2) -lt $audioData.Length) { $audioData[$i + 2] } else { 0 }
    $s3 = if (($i + 3) -lt $audioData.Length) { $audioData[$i + 3] } else { 0 }
    
    $b0 = ($s0) -bor (($s1 -band 0x03) -shl 6)
    $b1 = ($s1 -shr 2) -bor (($s2 -band 0x0F) -shl 4)
    $b2 = ($s2 -shr 4) -bor (($s3) -shl 2)
    
    $packedData[$outIdx++] = [byte]$b0
    $packedData[$outIdx++] = [byte]$b1
    $packedData[$outIdx++] = [byte]$b2
}

# Write final file to disk
[System.IO.File]::WriteAllBytes($OutputPath, $packedData)

Write-Host "8 bits wav file conversion complete ! Output file: $OutputPath" -ForegroundColor Green