using namespace System.Net

param($Request, $TriggerMetadata)

Write-Host "PowerShell HTTP trigger function processed a request."
$v = $Request.Query.v

$body = "No id."

if ($v) {
    $url = "https://www.youtube.com/watch?v=$v"
    $body = "Added $url"
}

if($Request.Body.FullUrl) {
    $url = ($Request.Body.FullUrl | ConvertFrom-Json)
    $body = "Added $url"
    $v = ($url -Replace "https://www.youtube.com/watch?v=","")
}

# replace with rclone config file contents (or set in function vars and reference here, or use maybe use keyvault for better security)
$fcontents = @"
[onedrive]
type = onedrive
"@
$fcontents | Out-file $env:TEMP\rc.conf

# remove stale files that previously failed
$Items = Get-ChildItem -Path "C:/home/site/wwwroot/ProcessUrl/FinishedDl/" | ? {$_.LastWriteTime -lt (Get-Date).AddMinutes(-50)}
if ($Items) {
    Write-Host "Removing stale objects:"
    $Items
    $Items | Remove-Item -Force -Recurse
}

if (!(Test-Path "C:\home\site\wwwroot\ProcessUrl\yt-dlp.exe")) { Invoke-WebRequest -Uri "https://github.com/yt-dlp/yt-dlp/releases/download/2022.03.08.1/yt-dlp.exe" -Outfile "C:\home\site\wwwroot\ProcessUrl\yt-dlp.exe" }
if (!(Test-Path "C:\home\site\wwwroot\ProcessUrl\rclone.exe")) { Invoke-WebRequest -Uri "https://streamz.z33.web.core.windows.net/rclone.exe" -Outfile "C:\home\site\wwwroot\ProcessUrl\rclone.exe" }
if (!(Test-Path "C:\home\site\wwwroot\ProcessUrl\ffmpeg.exe")) { Invoke-WebRequest -Uri "https://streamz.z33.web.core.windows.net/ffmpeg.exe" -Outfile "C:\home\site\wwwroot\ProcessUrl\ffmpeg.exe" }
if (!(Test-Path "C:\home\site\wwwroot\ProcessUrl\ffmpeg.exe")) { Invoke-WebRequest -Uri "https://streamz.z33.web.core.windows.net/ffprobe.exe" -Outfile "C:\home\site\wwwroot\ProcessUrl\ffmpeg.exe" }
if (!(Test-Path "C:\home\site\wwwroot\ProcessUrl\FinishedDL\")) { New-Item -Path "C:\home\site\wwwroot\ProcessUrl\" -Name "FinishedDL" -ItemType "directory" }

if ($v -and (Test-Path "C:\home\site\wwwroot\ProcessUrl\yt-dlp.exe")) {
    $tempGuid = (New-Guid).Guid
    New-Item -Path "C:\home\site\wwwroot\ProcessUrl\FinishedDl\" -Name $tempGuid -ItemType "directory"
    #New-Item -Path "C:\local\Temp\FinishedDl\" -Name $tempGuid -ItemType "directory"
    Set-Location $env:TEMP

    if(!(Test-Path "$env:TEMP\yt-dlp.exe")) { Copy-Item -Path "C:\home\site\wwwroot\ProcessUrl\yt-dlp.exe" -Destination "$env:TEMP\" }
    if(!(Test-Path "$env:TEMP\rclone.exe")) { Copy-Item -Path "C:\home\site\wwwroot\ProcessUrl\rclone.exe" -Destination "$env:TEMP\" }
    if(!(Test-Path "$env:TEMP\ffmpeg.exe")) { Copy-Item -Path "C:\home\site\wwwroot\ProcessUrl\ffmpeg.exe" -Destination "$env:TEMP\" }
    if(!(Test-Path "$env:TEMP\ffprobe.exe")) { Copy-Item -Path "C:\home\site\wwwroot\ProcessUrl\ffprobe.exe" -Destination "$env:TEMP\" }

    Write-Host "$tempGuid : Downloading $v"
    $dlPath = 'C:/home/site/wwwroot/ProcessUrl/FinishedDl/{0}/[[%(uploader)s]]%(title)s[[%(id)s]].%(ext)s' -f $tempGuid
    .\yt-dlp.exe $url -o $dlPath --no-check-certificate --windows-filenames --ffmpeg-location "$env:TEMP/" --no-mtime -f '(bestvideo[vcodec*=vp])+((bestaudio[ext*=webm]+bestaudio[ext*=m4a])/bestaudio)' `
        --compat-options multistreams --merge-output-format mkv --all-subs --embed-subs --add-metadata --embed-thumbnail
    Write-Host "$tempGuid : Uploading $v to OneDrive"
    try {
        .\rclone.exe copy "C:\home\site\wwwroot\ProcessUrl\FinishedDl\$tempGuid\" onedrive:OneDrive/Videos/YouTube/Functions/ --config  $env:TEMP/rc.conf
    } catch { Write-Host Rclone failure: $($PSItem.Exception.Message) }
    Write-Host "$tempGuid : Removing $v from temp storage"
    Remove-Item -Path "C:\home\site\wwwroot\ProcessUrl\FinishedDl\$tempGuid" -Force -Recurse
    Write-Host "$tempGuid : Completed $v"
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [HttpStatusCode]::OK
    Body = $body
})
