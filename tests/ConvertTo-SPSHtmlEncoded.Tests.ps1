# Direct unit tests for the private helper ConvertTo-SPSHtmlEncoded.
# It is otherwise only exercised indirectly through the HTML report exporters.
# Pure string logic, cross-platform.

BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUpdate.Common/SPSUpdate.Common.psd1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    Remove-Module -Name SPSUpdate.Common -Force -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-SPSHtmlEncoded' {
    It 'encodes each of the five HTML-significant characters' {
        InModuleScope SPSUpdate.Common {
            ConvertTo-SPSHtmlEncoded -Value '&' | Should -BeExactly '&amp;'
            ConvertTo-SPSHtmlEncoded -Value '<' | Should -BeExactly '&lt;'
            ConvertTo-SPSHtmlEncoded -Value '>' | Should -BeExactly '&gt;'
            ConvertTo-SPSHtmlEncoded -Value '"' | Should -BeExactly '&quot;'
            ConvertTo-SPSHtmlEncoded -Value "'" | Should -BeExactly '&#39;'
        }
    }

    It 'encodes a mixed string while leaving safe characters untouched' {
        InModuleScope SPSUpdate.Common {
            ConvertTo-SPSHtmlEncoded -Value 'DB <prod> & "co" ''x''' |
                Should -BeExactly 'DB &lt;prod&gt; &amp; &quot;co&quot; &#39;x&#39;'
        }
    }

    It 'returns an empty string for null or empty input' {
        InModuleScope SPSUpdate.Common {
            ConvertTo-SPSHtmlEncoded -Value $null | Should -BeExactly ''
            ConvertTo-SPSHtmlEncoded -Value '' | Should -BeExactly ''
        }
    }

    It 'accepts pipeline input' {
        InModuleScope SPSUpdate.Common {
            ('A & B' | ConvertTo-SPSHtmlEncoded) | Should -BeExactly 'A &amp; B'
        }
    }

    It 'leaves a string without special characters unchanged' {
        InModuleScope SPSUpdate.Common {
            ConvertTo-SPSHtmlEncoded -Value 'PlainName123' | Should -BeExactly 'PlainName123'
        }
    }
}
