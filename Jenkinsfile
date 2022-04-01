#!groovy
@Library('cpanel-pipeline-library@master') _

node('j16') {
    environment.check()

    def cpVersion = '11.74'
    def JOBS=16
    def perlVersion = '536'
    def productionBranch = 'bc536' // controls if we push to the Registry
    def TESTS="t/*.t t/testsuite/C-COMPILED/*/*.t"  // full run
    //def TESTS="t/*.t" // short version

    Map scmVars
    def testResults
    def registry_info = registry.getInfo()

    def SLACK_WEBHOOK = "https://hooks.slack.com/services/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"

    String startAt = sh (
                script: 'perl -e "print time()"',
                returnStdout: true
    ).trim()

    try {
        def email
        // EMAIL is defined at the folder level via the Folder Properties Plugin
        withFolderProperties {
            if (env.EMAIL == null) {
                error "EMAIL must be defined as a Folder Property"
            }
            email = env.EMAIL
        }

        notify.emailAtEnd([to:email]) {
            stage('Setup') {
                scmVars = checkout scm
                sh notifySlack(SLACK_WEBHOOK, currentBuild.result, scmVars, testResults, null)
                // implied 'INPROGRESS' to Bitbucket
                notifyBitbucket commitSha1: scmVars.GIT_COMMIT
            }

            def bc_image
            stage('Docker image build') {
                docker.withRegistry(registry_info.url, registry_info.credentialsId) {
                    bc_image = docker.build("pax/bc-node:${cpVersion}", "--pull --build-arg REGISTRY_HOST=${registry_info.host} --build-arg CPVERSION=${cpVersion} .")
                }
            }

            bc_image.inside {
                stage('Setup sandbox') {
                    // give it more time...
                    timeout(time: 5, unit: 'MINUTES') { sh 'sudo ./pre-setup.sh' }
                    // sh 'sudo ./pre-setup.sh'
                }

                stage('Makefile.PL') { sh makefileCommands() }

                // pek: the chown is so that the cleanWs() later doesn't have problems removing
                //   artifacts (that are created during the 'sudo make install')
                stage('make install') {
                    String commands = """
                        sudo make -j${JOBS} install
                        sudo chown -R jenkins:jenkins .
                    """
                    sh commands
                }

                stage('Unit tests') {
                    String commands = """
                        # smoke compiled tests and t/*.t
                        set +x
                        ## run as root, so we do not skip tests that check \$>
                        sudo bash -lc "PATH=/usr/local/cpanel/3rdparty/perl/${perlVersion}/bin:\$PATH /usr/local/cpanel/3rdparty/bin/prove -v -wm -j${JOBS} --formatter TAP::Formatter::JUnit ${TESTS}" >junit.xml || /bin/true
                        git diff t/testsuite/C-COMPILED/known_errors.txt > known_errors_delta.txt
                    """

                    timeout(time: 60, unit: 'MINUTES') { sh commands }
                }

                stage('Process results') {
                    archiveArtifacts artifacts: 'junit.xml'
                    archiveArtifacts artifacts: 'known_errors_delta.txt'

                    // pek: hudson.tasks.junit.TestResultSummary (failCount skipCount passCount totalCount)
                    testResults = junit testResults: 'junit.xml', keepLongStdio: false
                    if (_testsFailed(testResults)) {
                        currentBuild.result = 'UNSTABLE'
                    }
                }
            }
            // push self image to Registry ONLY IF: the work succeeds, and this is one of the fancy production branches
            if (currentBuild.result != 'UNSTABLE' && env.BRANCH_NAME == productionBranch) {
                stage('Docker push to internal Registry') {
                    docker.withRegistry(registry_info.url, registry_info.credentialsId) {
                        bc_image.push()
                    }
                }
            }
        }
    }
    finally {
        // scmVars will be null if we bomb out before the checkout (e.g. failure to set EMAIL in
        //   the folder properties)
        if (scmVars != null) {
            notifyBitbucket commitSha1: scmVars.GIT_COMMIT

            String out = sh (
                script: 'perl -E \'my $d = time() - '+ startAt +'; my $h = int( $d / 3600); printf("%02d h ", $h) if $h; printf( "%02d min %02d sec", int( ( $d % 3600 ) / 60 ), int( $d % 60 ) );\'',
                returnStdout: true
            ).trim()

            String elapsedTime = """runtime ${out}"""

            sh notifySlack(SLACK_WEBHOOK, currentBuild.result, scmVars, testResults, elapsedTime)
        }
        cleanWs()
    }
}

String notifySlack(String webhook, String status, Map scmVars, def testResults, String elapsedTime) {
    String reposURL = util.escapeHTML(bitbucket.getWebURL(scmVars.GIT_URL))
    String shortSHA = scmVars.GIT_COMMIT.substring(0,10)

    String color      = '#2eb886'
    String icon       = ''
    String extra_info = ''
    
    String buildname = """'${ scmVars.GIT_BRANCH }' ${ util.escapeHTML(BUILD_DISPLAY_NAME) }"""
    String message
    String subject

    if (null == status) {
        status = 'Pending'
        icon   = ':stopwatch:'
        color  = '#2b3bd9' // blue
        subject  = "Start smoking build ${buildname}"
    } else if (('FAILURE' == status) || (null == testResults)) {
        icon = ':red_circle:'
        color = '#cc0000' // red
        subject = "Failure when smoking build ${buildname}"
    }
    else if (_testsFailed(testResults)) {
        icon = ':warning:'
        color = '#f5ca46' // yellowish
        extra_info = """\\ntests result: ${testResults.failCount} failed. ${testResults.passCount} passed. ${testResults.totalCount} total."""
        subject = "Test failure from build ${buildname}"
    } else {
        icon = ':white_check_mark:' // check box
        color = '#2eb886' // green
        extra_info = """\\ntests result: ${testResults.failCount} failed. ${testResults.passCount} passed. ${testResults.totalCount} total."""
        subject = "Build Success ${buildname}"
    }

    String title   = """${icon} ${subject} """
    message = """
    Branch <${reposURL}/browse|${ scmVars.GIT_BRANCH }> ; Commit <${reposURL}/commits/${scmVars.GIT_COMMIT}|${ shortSHA }>
$extra_info
"""    

    if ( elapsedTime != null ) {
        message += """\\n${elapsedTime}"""
    }

    message += """\\n<${ util.escapeHTML(BUILD_URL) }|view Jenkins build ${ util.escapeHTML(BUILD_DISPLAY_NAME) }>"""

    return slack( webhook, title, message, color )
}


String slack(String webhook, String title, String message, String color) {
    String data = """
{
    "attachments": [
        {
            "title": "$title",
            "color": "$color",
            "text": "$message",
            "mrkdwn_in": [
                "text",
                "title"
            ]
        }
    ]
}
"""    
    data = data.replaceAll(/\n/, "")
    data = data.replaceAll(/\t/, " ")

    String commands = """
curl -X POST -H 'Content-type: application/json' --data '${data}' ${webhook}
"""

    return commands
}

def _testsFailed(testResults) {
    return testResults.failCount > 0
}

// Emacs' "balanced parenthesis" does not like the dollar square bracket variable
String makefileCommands() {
    return '''
        set +x
        /usr/local/cpanel/3rdparty/bin/perl -E 'say "# using cpanel perl version ", $]'
        rm -rf t/testsuite/t/extra/check-PL_strtab*
        /usr/local/cpanel/3rdparty/bin/perl Makefile.PL installdirs=vendor
        git checkout t
    '''
}
