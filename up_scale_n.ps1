
#Comands
$ffmpeg = ".\ffmpeg"
$ffprobe = ".\ffprobe"
$realesrgan = ".\realesrgan-ncnn-vulkan.exe"
$magick = "./ImageMagick/magick.exe"

$work_dir = "./worklab"
New-Item -ItemType Directory -Path $work_dir
# Target video
$in_video = "$work_dir/in_file"
# Extracted frames
$in_frames = "$work_dir/in_frames"
# Scaled frames
$out_frames = "$work_dir/out_frames"
# Finished frames
$out_scaled_frames = "$work_dir/out_production_frames"
# Colorized frames
$filtered_frames = "$work_dir/filtered_frames"
# Video output
$out_video = "$work_dir/out_file"

# Audio output
$out_audio = "$work_dir/out_audio"

New-Item -ItemType Directory -Path $work_dir
New-Item -ItemType Directory -Path $in_video
New-Item -ItemType Directory -Path $in_frames
New-Item -ItemType Directory -Path $out_frames
New-Item -ItemType Directory -Path $filtered_frames
New-Item -ItemType Directory -Path $out_scaled_frames
New-Item -ItemType Directory -Path $out_video


function ExtractFrames {

    param (
        
        [Parameter(Mandatory = $true)]
        [string]$ffmpeg,

        [Parameter(Mandatory = $true)]
        [string]$video,

        [Parameter(Mandatory = $true)]
        [string]$in_frames,

        [Parameter(Mandatory = $true)]
        [string]$frame_rate
    )

    $argument = "-i `"$video`" -qscale:v 1 -qmin 1 -qmax 1 -filter:v fps=`"$frame_rate`" `"$in_frames/frame%08d.jpg`""
    
    $comand = $ffmpeg + " " + $argument
    Invoke-Expression $comand
}

function GroupVideoFrames {

    param (
        
        [Parameter(Mandatory = $true)]
        [string]$ffmpeg,

        [Parameter(Mandatory = $true)]
        [string]$out_frames,

        [Parameter(Mandatory = $true)]
        [string]$in_video,

        [Parameter(Mandatory = $true)]
        [string]$out_video,

        [Parameter(Mandatory = $true)]
        [string]$frame_rate,

        [Parameter(Mandatory = $true)]
        [string]$video_name
    )

    $argument = "-framerate $frame_rate -i `"$out_frames/frame%08d.jpg`" -i `"$in_video`"  -map 0:v:0 -map 1:a:0 -c:a copy -c:v libx264 -r $frame_rate   -pix_fmt yuv420p  -video_track_timescale $($frame_rate)k   `"$out_video/$video_name`""
     
   
    Write-Output $argument
    $comand = $ffmpeg + " " + $argument
    Invoke-Expression $comand
}

function InvoqueRealesrgan {
    param (       
        [Parameter(Mandatory = $true)]
        [string]$realesrgan,

        [Parameter(Mandatory = $true)]
        [string]$in_frames,

        [Parameter(Mandatory = $true)]
        [string]$out_frames,
        [Parameter(Mandatory = $true)]
        [string]$model,
        [Parameter(Mandatory = $true)]
        [string]$scale
    )

    $argument = "-i `"$in_frames`" -o `"$out_frames`" -n `"$model`" -s $scale -f jpg" 

    return Start-Process -FilePath $realesrgan -ArgumentList  $argument  -PassThru

}  

function GetVideoFrameRate {
    param (       
        [Parameter(Mandatory = $true)]
        [string]$video,

        [Parameter(Mandatory = $true)]
        [string]$ffprobe
    )

    $ffprobe_arguments = "-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1  `"$video`""
   
    $comand = $ffprobe + " " + $ffprobe_arguments
    $output = (Invoke-Expression $comand).Trim()
    $duration = [math]::Round($output) 

    $ffprobe_arguments = "-v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 `"$video`""
    $comand = $ffprobe + " " + $ffprobe_arguments
    $output = (Invoke-Expression $comand).Trim()

    $fps_ffprobe = -1

    $rate = $output.Split('/')
    if ($rate.Count -eq 1) {
        $fps_ffprobe = [float]$rate[0]
    }
    if ($rate.Count -eq 2) {
        $fps_ffprobe = [float]$rate[0] / [float]$rate[1]
    }



    return @{
        Duration = $duration
        Fps      = $fps_ffprobe
    }
    
}


function GetEditedFrames {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$out_frames
    )

    # Get all files in the folder
    $files_edited = Get-ChildItem -Path $out_frames -File
    return $files_edited.Count
}

function ResumeRealEsrganScale {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$in_frames,

        [Parameter(Mandatory = $true)]
        [string]$out_frames,

        [Parameter(Mandatory = $true)]
        [string]$out_scaled_frames
    )

    # Get all files in the folder
    $files_in = Get-ChildItem -Path $in_frames -File

    # Initialize variables to store frame edit information
    $frames_moved = 0
    $frames_extracted = 0

    # Loop through each file
    foreach ($file in $files_in) {

        # Check if the file has been edited

        $frames_extracted++

        if (Test-Path -Path "$out_frames\$file") {

            $frames_moved++

            # Copy the edited frame to the destination folder
            $editedFramePath = "$in_frames\$file"
            $destinationPath = "$out_scaled_frames\$file"
            Move-Item -Path $editedFramePath -Destination $destinationPath
        }
    }

    return @{
        FramesExtracted = $frames_extracted
        FramesMoved     = $frames_moved
    }
}

function ImageMagic {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$out_frame,
        [Parameter(Mandatory = $true)]
        [string]$filtered_frame,
        [Parameter(Mandatory = $true)]
        [string]$magick

    )

    # Comando para mejorar la imagen utilizando ImageMagick
    $brillo = 100
    $saturacion = 200
    $contraste = "0%"

    $argument = "convert $out_frame -modulate $brillo,$saturacion  -level $contraste  $filtered_frame"

    Write-Output $magick+" "+$argument

    Start-Process -FilePath $magick -ArgumentList  $argument  -PassThru -NoNewWindow

}

function Colorise_Image {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$out_frames,
        [Parameter(Mandatory = $true)]
        [string]$filtered_frames,
        [Parameter(Mandatory = $true)]
        [string]$magick

    )

    # Initialize variables to store frame edit information
    $frames_colorized = 0

    # Get all files in the folder
    $files_in = Get-ChildItem -Path $out_frames -File

    foreach ($file in $files_in) {
   
            if (-not (Test-Path -Path "$filtered_frames\$file")) {
                $frames_colorized++
                Write-Output "Filtered frames: $frames_colorized "
                # Copy the edited frame to the destination folder
                $editedFramePath = "$out_frames\$file"
                $destinationPath = "$filtered_frames\$file"
                ImageMagic -out_frame $editedFramePath  -filtered_frame $destinationPath -magick $magick
            } 
        }
}

function ExtractAudio {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$out_audio,
        [Parameter(Mandatory = $true)]
        [string]$video,     
        [Parameter(Mandatory = $true)]
        [string]$ffmpeg
    )

    $argument = " -i `"$video`"  `"$out_audio`"" 
    Write-Output $ffmpeg+" "+$argument

    Start-Process -FilePath $ffmpeg -ArgumentList  $argument  -PassThru -NoNewWindow

}


function AudacityAudio {
    [CmdletBinding()]
    param (  
        [Parameter(Mandatory = $true)]
        [string]$audacity
    )

    $argument = " -i `"$video`"   `"$out_audio`"" 
    Write-Output $ffmpeg+" "+$argument

    Start-Process -FilePath $ffmpeg -ArgumentList  $argument  -PassThru -NoNewWindow

}

function Info {

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$video,
        [Parameter(Mandatory = $true)]
        [int]$fps,
        [Parameter(Mandatory = $true)]
        [int]$duration, 
        [Parameter(Mandatory = $true)]
        [int]$extracted_frames, 
        [Parameter(Mandatory = $true)]
        [int]$edited_frames, 
        [Parameter(Mandatory = $true)]
        [int]$total_frames, 
        [Parameter(Mandatory = $false)]
        [int]$percent
    )

    Clear-Host
    Write-Output "Video processing with Real-ESRGAN"
    Write-Output "Title: $video"
    Write-Output "FPS: $fps" 
    Write-Output "Duration: $duration  seconds"
    Write-Output "Total Frames: $total_frames"
    Write-Output "-----------------------------"

    Write-Output "Frames Remain: $extracted_frames"
    Write-Output "Edited Frames: $edited_frames"

    Write-Output "Percent:  $([Math]::Round($percent)) %"
  
}

function Main {

    # Obtener la lista de videos
    $lista_videos = Get-ChildItem -Path $in_video -File -Recurse -Filter "*.mp4"

    # Iterar sobre la lista de videos

    foreach ($video in $lista_videos) {

        $frame_rate = GetVideoFrameRate -video  "$in_video/$video" -ffprobe $ffprobe
        $fps = [Math]::Round($frame_rate.Fps)
        $duration = $frame_rate.Duration        

        $output = ResumeRealEsrganScale -in_frames $in_frames -out_frames $out_frames -out_scaled_frames $out_scaled_frames
        $extracted_frames = $output.FramesExtracted
        $moved_frames = $output.FramesMoved
        Write-Output "Frames Moved: $moved_frames"

        $edited_frames = GetEditedFrames -out_frames $out_frames  

        $total_frames = $fps * $duration
       
        Info -video $video -fps $fps -duration $duration -edited_frames $edited_frames -extracted_frames $extracted_frames -total_frames $total_frames 

        if ( $edited_frames -lt 1 ) {
            Write-Information ""
            Write-Information "Extracting frames"
            Write-Information ""

            ExtractFrames  -ffmpeg $ffmpeg -video "$in_video/$video" -in_frames $in_frames  -frame_rate $fps
        
            $output = ResumeRealEsrganScale -in_frames $in_frames -out_frames $out_frames -out_scaled_frames $out_scaled_frames
            $extracted_frames = $output.FramesExtracted
            $moved_frames = $output.FramesMoved
        
        }

        #Colorise_Image -out_frames $in_frames  -filtered_frames $filtered_frames -magick $magick

        if ( $true) {
            Write-Information ""
            Write-Information "Extracting Audio"
            Write-Information ""

            ExtractAudio  -ffmpeg $ffmpeg -video "$in_video/$video" -out_audio "$out_audio/$video.wav"
        
        }

        Write-Information ""
        Write-Information " Real-ESRGAN"
        Write-Information ""

        #InvoqueRealesrgan -realesrgan $realesrgan -in_frames $in_frames -out_frames $out_frames -model "re-focus"
        InvoqueRealesrgan -realesrgan $realesrgan -in_frames  $filtered_frames -out_frames $out_frames -model "focus" -scale 1

        $realesrgan_ncnn_vulkan = Get-Process -Name "realesrgan-ncnn-vulkan"

        while (-not $realesrgan_ncnn_vulkan.HasExited ) {

            Clear-Host

            $now_edited_frames = GetEditedFrames -out_frames $out_frames  
            $now_edited_frames = $now_edited_frames - $edited_frames
            $percent = ($now_edited_frames / $extracted_frames) * 100

            Info -video $video -fps $fps -duration $duration -edited_frames $now_edited_frames -extracted_frames $extracted_frames -total_frames $total_frames   -percent $percent
               
    
            Start-Sleep -Seconds 1
        }
           
           
        GroupVideoFrames -ffmpeg $ffmpeg -out_frames $out_frames -in_video "$in_video/$video" -frame_rate $fps -out_video $out_video  -video_name $video


        Write-Information ""
        Write-Information " Filter Images"
        Write-Information ""

        Colorise_Image -out_frames $out_frames  -filtered_frames $filtered_frames -magick $magick

        $filtered_frames_final = GetEditedFrames -out_frames $filtered_frames 

        if (( $filtered_frames_final -gt $total_frames ) -or ( $filtered_frames_final -eq $total_frames )) {

            Write-Information ""
            Write-Information " Make new video"
            Write-Information ""

            GroupVideoFrames -ffmpeg $ffmpeg -out_frames $out_frames -in_video "$in_video/$video" -frame_rate $fps -out_video $out_video  -video_name $video

            #GroupVideoFrames -ffmpeg $ffmpeg -out_frames $filtered_frames -in_video "$in_video/$video" -frame_rate $fps -out_video $out_video  -video_name $video
        

        }
   
    }

}


Main
