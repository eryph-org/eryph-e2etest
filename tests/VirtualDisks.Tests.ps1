#Requires -Version 7.4
#Requires -Module Pester
#Requires -Module Assert
BeforeAll {
  . $PSScriptRoot/../Use-Settings.ps1
  . $PSScriptRoot/Helpers.ps1
  Setup-GenePool
}

Describe "VirtualDisks" {
  BeforeEach {
    $project = New-TestProject
    $catletName = New-CatletName
    $diskName = "testdisk-$(Get-Date -Format 'yyyyMMddHHmmss')"
  }

  Context "Get-CatletDisk" {
    It "Returns all disks" {
      $disk = New-CatletDisk -Name $diskName -Size 5 -ProjectName $project.Name -Location test
      $config = @"
parent: dbosoft/e2etests-os/base
drives:
- name: '$diskName'
  location: test
"@
      $catlet = New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
    
      $catletDisks = Get-CatletDisk -ProjectName $project.Name
      $catletDisks | Should -HaveCount 2

      $catletDisks | Assert-Any { $_.Id -eq $disk.Id }
      $catletDisks | Assert-All { $_.Project.Id -eq $project.Id -and $_.Project.Name -eq $project.Name }
      $catletDisks | Assert-All { $_.Environment -eq "default" }
      $catletDisks | Assert-All { $_.DataStore -eq "default" }
      $catletDisks | Assert-All { $_.AttachedCatlets.Count -eq 1 ` -and $_.AttachedCatlets[0].CatletId -eq $catlet.Id ` }
      
      $sdaDisk = $catletDisks | Where-Object { $_.Name -eq "sda" }
      $sdaDisk | Should -HaveCount 1
      $sdaDisk.ParentId | Should -Not -BeNull

      $sdaParentDisk = Get-CatletDisk -Id $sdaDisk.ParentId
      $sdaParentDisk | Should -Not -BeNull
      $sdaParentDisk.Location | Should -BeNull
      $sdaParentDisk.Name | Should -Be "sda"
      $sdaParentDisk.Project.Name | Should -Be "default"
      $sdaParentDisk.Environment | Should -Be "default"
      $sdaParentDisk.DataStore | Should -Be "default"
      $sdaParentDisk.ParentId | Should -BeNull
      $sdaParentDisk.Gene | Should -Not -BeNull
      $sdaParentDisk.Gene.GeneSet | Should -BeLike "dbosoft/ubuntu-24.04/*"
      $sdaParentDisk.Gene.Name | Should -BeLike "sda"
      $sdaParentDisk.Gene.Architecture | Should -Be "hyperv/amd64"
    }
  }

  Context "New-CatletDisk" {
    It "Creates a disk" {
      $disk = New-CatletDisk -Name $diskName -Size 5 -ProjectName $project.Name -Location test

      $disk | Should -Not -BeNull
      $disk.Name | Should -Be $diskName
      $disk.Project.Id | Should -Be $project.Id
      $disk.Project.Name | Should -Be $project.Name
      $disk.SizeBytes | Should -Be 5GB
      $disk.Environment | Should -Be "default"
      $disk.DataStore | Should -Be "default"
      $disk.Location | Should -Be "test"
      $disk.Path | Should -Exist
      $disk.Path | Should -BeLike "*\p_$($project.Name)\test\$diskName.vhdx"

      $vhd = Get-VHD -Path $disk.Path
      $vhd | Should -Not -BeNull
      $vhd.Size | Should -Be 5GB
      $vhd.VhdFormat | Should -Be VHDX
      $vhd.VhdType | Should -Be Dynamic
    }
  }

  Context "Remove-CatletDisk" {
    It "Does not remove the disk if it is attached to a catlet" {
      $disk = New-CatletDisk -Name $diskName -Size 5 -ProjectName $project.Name -Location test
      $config = @"
parent: dbosoft/e2etests-os/base
drives:
- name: '$diskName'
  location: test
"@
      New-Catlet -Name $catletName -ProjectName $project.Name -Config $config
      
      { Remove-CatletDisk -Id $disk.Id -Force } |
        Should -Throw "*The disk is attached to a virtual machine and cannot be deleted*"
    }

    It "Removes the disk" {
      $disk = New-CatletDisk -Name $diskName -Size 5 -ProjectName $project.Name -Location test
      $disk.Path | Should -Exist

      Remove-CatletDisk -Id $disk.Id -Force

      $disk.Path | Should -Not -Exist

      # Explicitly check that the disk is not returned by the API
      # anymore. We use a delete flag in the database.
      $catletDisks = Get-CatletDisk -ProjectName $project.Name
      $catletDisks | Assert-All { $_.Name -ine $diskName }
    }
  }

  Context "Inventory" {
    It "Updates inventory when disk is added and removed in file system" {
      $storageIdentifier = "st-$(Get-Date -Format 'yyyyMMddHHmmss')"
      $diskPath = Join-Path $EryphSettings.DefaultDiskStorePath $storageIdentifier "$diskName.vhdx"
      New-VHD -Path $diskPath -SizeBytes 64MB -Dynamic

      Wait-Assert {
        $catletDisks = Get-CatletDisk
        $catletDisk = $catletDisks | Where-Object { $_.Path -eq $diskPath }
        $catletDisk | Should -HaveCount 1
        $catletDisk.Name | Should -Be $diskName
        $catletDisk.SizeBytes | Should -Be 64MB
        $catletDisk.Environment | Should -Be "default"
        $catletDisk.DataStore | Should -Be "default"
        $catletDisk.Location | Should -Be $storageIdentifier
        $catletDisk.Path | Should -Be $diskPath
      }

      Remove-Item -Path $diskPath -Force
     
      Wait-Assert {
        $catletDisks = Get-CatletDisk
        $catletDisks | Assert-All { $_.Name -ne $diskName }
      }
    }
  }

  AfterEach {
    Remove-EryphProject -Id $project.Id -Force
  }
}
