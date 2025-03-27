
export TYPE="export"
export WORKSPACE_URL=""
export SOURCE_PROJECT_NAME=""
export TARGET_PROJECT_NAME=""
export API_KEY=""
export WORK_DIR="/tmp/ml-exp"
export DEBUG="false"

function usage()
{
    echo "This script aims at exporting/importing experiments from one CML project to anothe one "
    echo ""
    echo "Usage is the following : "
    echo ""
    echo "./move-experiments.sh"
    echo "  -h --help"
    echo ""
    echo " --type=$TYPE : Either export or import (Required)"
    echo " --workspace-url=$WORKSPACE_URL URL Of source or target workspace in format: https://workspace:port/ (Required)"
    echo " --source-project-name=$SOURCE_PROJECT_NAME Name in the source workspace of source project (Required)"
    echo " --target-project-name=$TARGET_PROJECT_NAME Name in the target workspace of target project (Only required for export)"
    echo " --api-key=$API_KEY CML API Key of a user that have enough rights to read/write on projects (Required)"
    echo " --work-dir=$WORK_DIR directory where to store experiments (Optional) "
    echo " --debug=$DEBUG to enable debug or not"
    echo ""
    echo ""
}



while [ "$1" != "" ]; do
    PARAM=`echo $1 | awk -F= '{print $1}'`
    VALUE=`echo $1 | awk -F= '{print $2}'`
    case $PARAM in
        -h | --help)
            usage
            exit
            ;;
        --type)
            TYPE=$VALUE
            ;;
        --workspace-url)
            WORKSPACE_URL=$VALUE
            ;;
        --source-project-name)
            SOURCE_PROJECT_NAME=$VALUE
            ;;    
        --target-project-name)
            TARGET_PROJECT_NAME=$VALUE
            ;;
        --api-key)
            API_KEY=$VALUE
            ;;
        --work-dir)
            WORK_DIR=$VALUE
            ;;
        --debug)
            DEBUG=$VALUE
            ;;
        *)
            ;;
    esac
    shift
done

#### INTERNAL VARS
#headers="-H "authorization: Bearer $API_KEY" -H 'Accept: application/json'"
api_url="${WORKSPACE_URL}api/v2"


if [ "${DEBUG}" = "true" ] ; then
    set +x 
    env
fi


### EXPORT ###
if [ "${TYPE}" == "export" ] ; then

    mkdir -p $WORK_DIR
    mkdir -p ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}

    # 1. Get Project ID
    # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json"  https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects | jq
    S_PROJECT_ID=$(curl -k -H "authorization: Bearer $API_KEY" -H 'Accept: application/json' ${api_url}/projects | jq -r ".projects[] | select(.name == \"${SOURCE_PROJECT_NAME}\") | .id")
    echo "Project ID is: $S_PROJECT_ID"
    echo "$S_PROJECT_ID" > ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/id


    # # 2. Get List of Experiments
    # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json"  https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/ur3o-j4hq-ivcd-a7xy/experiments | jq
    EXPS=$(curl -k -H "authorization: Bearer $API_KEY" -H 'Accept: application/json' ${api_url}/projects/${S_PROJECT_ID}/experiments | jq -c '.experiments[] ') 
    if [ "${DEBUG}" = "true" ] ; then
        echo $EXPS 
    fi
    for exp in $EXPS ; do
        exp_id=$(echo $exp | jq -r '.id')
        exp_name=$(echo $exp | jq -r '.name')
        echo "Treating exp: ${exp_name}"

        mkdir -p ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/${exp_name}
        echo $exp_id > ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/${exp_name}/id
        echo $exp > ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/${exp_name}/def

        # # 2.1. Foreach Experiment, create a dir with id => Get all runs and foreach run, save it to a file run-$RUN_ID.json
        # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json"  https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/ur3o-j4hq-ivcd-a7xy/experiments/ny6y-rs3g-8hdc-clgw/runs | jq

        RUN_IDS=$(curl -k -H "authorization: Bearer $API_KEY" -H 'Accept: application/json' ${api_url}/projects/${S_PROJECT_ID}/experiments/${exp_id}/runs | jq -c -r '.experiment_runs[] | .id')
        if [ "${DEBUG}" = "true" ] ; then
            echo $RUNS
        fi
        echo $RUN_IDS
        for run_id in $RUN_IDS ; do
            run_details=$(curl -k -H "authorization: Bearer $API_KEY" -H 'Accept: application/json' ${api_url}/projects/${S_PROJECT_ID}/experiments/${exp_id}/runs/${run_id})
            echo $run_details > ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/${exp_name}/run-${run_id}.json
        done

    done


elif [ "${TYPE}" == "import" ] ; then
### IMPORT

    mkdir -p $WORK_DIR
    mkdir -p ${WORK_DIR}/target-${TARGET_PROJECT_NAME}

    export T_PROJECT_ID=$(curl -k -H "authorization: Bearer $API_KEY" -H 'Accept: application/json' ${api_url}/projects | jq -r ".projects[] | select(.name == \"${TARGET_PROJECT_NAME}\") | .id")
    echo "Project ID is: $T_PROJECT_ID"
    echo "$T_PROJECT_ID" > ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/id

    # 1. Foreach Experiment => Create a new experiment (and store its id)
    # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPOST  -d@experiment.json https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/119e-1g6c-53ws-ggdr/experiments
    # with experiment.json:
    # {
    # "project_id": "119e-1g6c-53ws-ggdr",
    # "name": "test"
    # }

    find ${WORK_DIR}/source-${SOURCE_PROJECT_NAME}/* -type d -print0 | while IFS= read -r -d $'\0' exp_dir ; do

        exp_id=$( cat ${exp_dir}/id)
        export exp_name=$( basename $exp_dir )
        echo "Treating ${exp_name} with id: $exp_id"

        mkdir -p ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}
        cp ${exp_dir}/def ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/

        envsubst < exp_def.json > first_def.json

        CREATE_EXP=$(curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPOST -d@first_def.json ${api_url}/projects/${T_PROJECT_ID}/experiments | jq )
        export exp_id_target=$(echo $CREATE_EXP | jq -r '.id')
        echo $exp_id_target > ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/id
        echo "Succesfully create experiment with id: $exp_id_target"

        rm -rf first_def.json
        
        # # 1.1. (Optional) Update the experiment with definition of previous experiment
        # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPATCH  -d@experiment-def.json https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/119e-1g6c-53ws-ggdr/experiments/zpa6-ydgn-oecj-55ry


        find ${exp_dir}/* -type f -name "run*" -print0 | while IFS= read -r -d $'\0' run_file ; do
            # # 2. Foreach run => Create a run (and store its id)
            # {
            # "project_id": "119e-1g6c-53ws-ggdr",
            # "experiment_id": "zpa6-ydgn-oecj-55ry"
            # }
            # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPOST  -d@run.json https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/119e-1g6c-53ws-ggdr/experiments/zpa6-ydgn-oecj-55ry/runs

            echo "treating run: $run_file"
            cp $run_file ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/
            run_basename=$(basename $run_file)
            run_id=$( cat $run_file | jq -r '.id' )

            envsubst < run_def.json > run_def_first.json

            CREATE_RUN=$(curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPOST -d@run_def_first.json ${api_url}/projects/${T_PROJECT_ID}/experiments/${exp_id_target}/runs | jq )
            export run_id_target=$(echo $CREATE_RUN | jq -r '.id')
            echo "Succesfully create run with id: $run_id_target"
            rm -rf run_def_first.json

            # # 2.1. Update the run
            # curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPATCH  -d@run1.json https://workspace2.apps.mygpu-8.vpc.cloudera.com/api/v2/projects/119e-1g6c-53ws-ggdr/experiments/zpa6-ydgn-oecj-55ry/runs/bz94-p4hs-yf5r-9p6k

            sed -i -e "s/${exp_id}/${exp_id_target}/" ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/${run_basename}
            sed -i -e "s/${run_id}/${run_id_target}/" ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/${run_basename}
            cp ${WORK_DIR}/target-${TARGET_PROJECT_NAME}/${exp_name}/${run_basename} run_full_def.json

            curl -k -H "authorization: Bearer $API_KEY" -H "Accept: application/json" -XPATCH -d@run_full_def.json ${api_url}/projects/${T_PROJECT_ID}/experiments/${exp_id_target}/runs/${run_id_target}
            echo "Succesfully updated run with id: $run_id_target"

            rm -rf run_full_def.json
        
        done 

    done
fi 


if [ "${DEBUG}" = "true" ] ; then
    env
    set -x 
fi
