. "$psscriptroot\..\lib\core.ps1"
. "$psscriptroot\..\lib\install.ps1"
. "$psscriptroot\..\lib\unix.ps1"
. "$psscriptroot\Scoop-TestLib.ps1"

$repo_dir = (Get-Item $MyInvocation.MyCommand.Path).directory.parent.FullName
$isUnix = is_unix

describe "is_directory" {
    beforeall {
        $working_dir = setup_working "is_directory"
    }

    it "is_directory recognize directories" {
        is_directory "$working_dir\i_am_a_directory" | Should be $true
    }
    it "is_directory recognize files" {
        is_directory "$working_dir\i_am_a_file.txt" | Should be $false
    }

    it "is_directory is falsey on unknown path" {
        is_directory "$working_dir\i_do_not_exist" | Should be $false
    }
}

describe "movedir" {
    $extract_dir = "subdir"
    $extract_to = $null

    beforeall {
        $working_dir = setup_working "movedir"
    }

    it "moves directories with no spaces in path" -skip:$isUnix {
        $dir = "$working_dir\user"
        movedir "$dir\_tmp\$extract_dir" "$dir\$extract_to"

        "$dir\test.txt" | should FileContentMatch "this is the one"
        "$dir\_tmp\$extract_dir" | should not exist
    }

    it "moves directories with spaces in path" -skip:$isUnix {
        $dir = "$working_dir\user with space"
        movedir "$dir\_tmp\$extract_dir" "$dir\$extract_to"

        "$dir\test.txt" | should FileContentMatch "this is the one"
        "$dir\_tmp\$extract_dir" | should not exist

        # test trailing \ in from dir
        movedir "$dir\_tmp\$null" "$dir\another"
        "$dir\another\test.txt" | should FileContentMatch "testing"
        "$dir\_tmp" | should not exist
    }

    it "moves directories with quotes in path" -skip:$isUnix {
        $dir = "$working_dir\user with 'quote"
        movedir "$dir\_tmp\$extract_dir" "$dir\$extract_to"

        "$dir\test.txt" | should FileContentMatch "this is the one"
        "$dir\_tmp\$extract_dir" | should not exist
    }
}

describe "unzip_old" {
    beforeall {
        $working_dir = setup_working "unzip_old"
    }

    function test-unzip($from) {
        $to = strip_ext $from

        if(is_unix) {
            unzip_old ($from -replace '\\','/') ($to -replace '\\','/')
        } else {
            unzip_old ($from -replace '/','\') ($to -replace '/','\')
        }

        $to
    }

    context "zip file size is zero bytes" {
        $zerobyte = "$working_dir\zerobyte.zip"
        $zerobyte | should exist

        it "unzips file with zero bytes without error" -skip:$isUnix {
            # some combination of pester, COM (used within unzip_old), and Win10 causes a bugged return value from test-unzip
            # `$to = test-unzip $zerobyte` * RETURN_VAL has a leading space and complains of $null usage when used in PoSH functions
            $to = ([string](test-unzip $zerobyte)).trimStart()

            $to | should not match '^\s'
            $to | should not be NullOrEmpty

            $to | should exist

            (Get-ChildItem $to).count | should be 0
        }
    }

    context "zip file is small in size" {
        $small = "$working_dir\small.zip"
        $small | should exist

        it "unzips file which is small in size" -skip:$isUnix {
            # some combination of pester, COM (used within unzip_old), and Win10 causes a bugged return value from test-unzip
            # `$to = test-unzip $small` * RETURN_VAL has a leading space and complains of $null usage when used in PoSH functions
            $to = ([string](test-unzip $small)).trimStart()

            $to | should not match '^\s'
            $to | should not be NullOrEmpty

            $to | should exist

            # these don't work for some reason on appveyor
            #join-path $to "empty" | should exist
            #(gci $to).count | should be 1
        }
    }
}

describe "shim" {
    beforeall {
        $working_dir = setup_working "shim"
        $shimdir = shimdir
        $(ensure_in_path $shimdir) | out-null
    }

    it "links a file onto the user's path" -skip:$isUnix {
        { get-command "shim-test" -ea stop } | should throw
        { get-command "shim-test.ps1" -ea stop } | should throw
        { get-command "shim-test.cmd" -ea stop } | should throw
        { shim-test } | should throw

        shim "$working_dir\shim-test.ps1" $false "shim-test"
        { get-command "shim-test" -ea stop } | should not throw
        { get-command "shim-test.ps1" -ea stop } | should not throw
        { get-command "shim-test.cmd" -ea stop } | should not throw
        shim-test | should be "Hello, world!"
    }

    context "user with quote" {
        it "shims a file with quote in path" -skip:$isUnix {
            { get-command "shim-test" -ea stop } | should throw
            { shim-test } | should throw

            shim "$working_dir\user with 'quote\shim-test.ps1" $false "shim-test"
            { get-command "shim-test" -ea stop } | should not throw
            shim-test | should be "Hello, world!"
        }
    }

    aftereach {
        rm_shim "shim-test" $shimdir
    }
}

describe "rm_shim" {
    beforeall {
        $working_dir = setup_working "shim"
        $shimdir = shimdir
        $(ensure_in_path $shimdir) | out-null
    }

    it "removes shim from path" -skip:$isUnix {
        shim "$working_dir\shim-test.ps1" $false "shim-test"

        rm_shim "shim-test" $shimdir

        { get-command "shim-test" -ea stop } | should throw
        { get-command "shim-test.ps1" -ea stop } | should throw
        { get-command "shim-test.cmd" -ea stop } | should throw
        { shim-test } | should throw
    }
}

Describe "get_app_name_from_ps1_shim" {
    BeforeAll {
        $working_dir = setup_working "shim"
        $shimdir = shimdir
        $(ensure_in_path $shimdir) | Out-Null
    }

    It "returns empty string if file does not exist" -skip:$isUnix {
        get_app_name_from_ps1_shim "non-existent-file" | should be ""
    }

    It "returns app name if file exists and is a shim to an app" -skip:$isUnix {
        mkdir -p "$working_dir/mockapp/current/"
        Write-Output "" | Out-File "$working_dir/mockapp/current/mockapp.ps1"
        shim "$working_dir/mockapp/current/mockapp.ps1" $false "shim-test"
        $shim_path = (get-command "shim-test.ps1").Path
        get_app_name_from_ps1_shim "$shim_path" | should be "mockapp"
    }

    It "returns app name if file exists and is a shim to an app cerca August 2018" -skip:$isUnix {
        Write-Output '$path = join-path "$psscriptroot" "..\apps\vim\current\vim.exe"' | Out-File "$working_dir/moch-shim.ps1" -Encoding utf8
        Write-Output 'if($myinvocation.expectingInput) { $input | & $path  @args } else { & $path  @args }' | Out-File "$working_dir/moch-shim.ps1" -Append -Encoding utf8
        get_app_name_from_ps1_shim "$working_dir/moch-shim.ps1" | should be "vim"
    }

    It "returns empty string if file exists and is not a shim" -skip:$isUnix {
        Write-Output "lorem ipsum" | Out-File -Encoding ascii "$working_dir/mock-shim.ps1"
        get_app_name_from_ps1_shim "$working_dir/mock-shim.ps1" | should be ""
    }

    AfterEach {
        if (Get-Command "shim-test" -ErrorAction SilentlyContinue) {
            rm_shim "shim-test" $shimdir -ErrorAction SilentlyContinue
        }
        Remove-Item -Force -Recurse -ErrorAction SilentlyContinue "$working_dir/mockapp"
        Remove-Item -Force -ErrorAction SilentlyContinue "$working_dir/moch-shim.ps1"
    }
}

describe "ensure_robocopy_in_path" {
    $shimdir = shimdir $false
    mock versiondir { $repo_dir }

    beforeall {
        reset_aliases
    }

    context "robocopy is not in path" {
        it "shims robocopy when not on path" -skip:$isUnix {
            mock gcm { $false }
            Get-Command robocopy | should be $false

            ensure_robocopy_in_path

            "$shimdir/robocopy.ps1" | should exist
            "$shimdir/robocopy.exe" | should exist

            # clean up
            rm_shim robocopy $(shimdir $false) | out-null
        }
    }

    context "robocopy is in path" {
        it "does not shim robocopy when it is in path" -skip:$isUnix {
            mock gcm { $true }
            ensure_robocopy_in_path

            "$shimdir/robocopy.ps1" | should not exist
            "$shimdir/robocopy.exe" | should not exist
        }
    }
}

describe 'sanitary_path' {
  it 'removes invalid path characters from a string' {
    $path = 'test?.json'
    $valid_path = sanitary_path $path

    $valid_path | should be "test.json"
  }
}

describe 'app' {
    it 'parses the bucket name from an app query' {
        $query = "C:\test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be "C:\test.json"
        $bucket | should be $null
        $version | should be $null

        $query = "test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be "test.json"
        $bucket | should be $null
        $version | should be $null

        $query = ".\test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be ".\test.json"
        $bucket | should be $null
        $version | should be $null

        $query = "..\test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be "..\test.json"
        $bucket | should be $null
        $version | should be $null

        $query = "\\share\test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be "\\share\test.json"
        $bucket | should be $null
        $version | should be $null

        $query = "https://example.com/test.json"
        $app, $bucket, $version = parse_app $query
        $app | should be "https://example.com/test.json"
        $bucket | should be $null
        $version | should be $null

        $query = "test"
        $app, $bucket, $version = parse_app $query
        $app | should be "test"
        $bucket | should be $null
        $version | should be $null

        $query = "extras/enso"
        $app, $bucket, $version = parse_app $query
        $app | should be "enso"
        $bucket | should be "extras"
        $version | should be $null

        $query = "test-app"
        $app, $bucket, $version = parse_app $query
        $app | should be "test-app"
        $bucket | should be $null
        $version | should be $null

        $query = "test-bucket/test-app"
        $app, $bucket, $version = parse_app $query
        $app | should be "test-app"
        $bucket | should be "test-bucket"
        $version | should be $null

        $query = "test-bucket/test-app@1.8.0"
        $app, $bucket, $version = parse_app $query
        $app | should be "test-app"
        $bucket | should be "test-bucket"
        $version | should be "1.8.0"

        $query = "test-bucket/test-app@1.8.0-rc2"
        $app, $bucket, $version = parse_app $query
        $app | should be "test-app"
        $bucket | should be "test-bucket"
        $version | should be "1.8.0-rc2"
    }
}
