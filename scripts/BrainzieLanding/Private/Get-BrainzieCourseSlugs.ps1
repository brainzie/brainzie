<#
.SYNOPSIS
    Internal. The course registry: course number -> site folder slug.

.DESCRIPTION
    Single source of truth for which Blazor course apps exist and where their
    published output lives (site/courses/<slug>/app). When the new-course skill
    scaffolds a course with interactive lessons, it adds an entry here.
#>
function Get-BrainzieCourseSlugs {
    @{
        '08' = '08-software-mixed'
    }
}
