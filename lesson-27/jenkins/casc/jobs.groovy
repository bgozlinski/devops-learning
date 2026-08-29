// Job DSL - definicje pipeline'ow testowych dla obu zadan domowych.
// Tresc pipeline'ow jest czytana z plikow z katalogu lesson-27/pipelines,
// zamontowanego do kontrolera pod /var/jenkins_pipelines.
def pipelinesDir = '/var/jenkins_pipelines'

pipelineJob('lesson-27-static-agent') {
    description('Zadanie domowe 1 - build wymuszony na stalym agencie linux-worker-01.')
    definition {
        cps {
            script(new File("${pipelinesDir}/Jenkinsfile.static-agent").text)
            sandbox(true)
        }
    }
}

pipelineJob('lesson-27-docker-agent') {
    description('Zadanie domowe 2 - build na agencie tworzonym w kontenerze Docker.')
    definition {
        cps {
            script(new File("${pipelinesDir}/Jenkinsfile.docker-agent").text)
            sandbox(true)
        }
    }
}
