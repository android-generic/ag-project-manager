#!/bin/bash

# SPDX-License-Identifier: GPL-2.0
#
# Android-Generic Project Manager
# Copyright (C) 2021-2023 Android-Generic Team
#
# ag-project-manager.sh 

PWD=$(pwd)
TEMP_PATH=$(mktemp -d)
SCRIPT_PATH=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
AG_CONFIG_PATH=~/.config/ag
echo "SCRIPT_PATH: $SCRIPT_PATH"
export PATH="$SCRIPT_PATH/core-menu/includes/:$PATH"
source $SCRIPT_PATH/core-menu/includes/easybashgui
source $SCRIPT_PATH/core-menu/includes/common.sh
export supertitle="Android Generic Project Manager"
export supericon="$SCRIPT_PATH/assets/ag-logo.png"

# Create config folder in ~/.config
mkdir -p $AG_CONFIG_PATH

# Look for "-d|--debug" options flag
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -d|--debug)
            DEBUG=true
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Check if the config folder contains a project.cfg file that contains the location of the users projects folder
# If not, ask the location of the projects folder on the local machine and save the variable to the config file
if [ ! -f $AG_CONFIG_PATH/project.cfg ]; then
    message "Please enter the location of your projects folder: "
    dselect 
    projects_path=$(0<"${dir_tmp}/${file_tmp}")
    echo "projects_path = $projects_path"
    echo "projects_path=$projects_path" >>$AG_CONFIG_PATH/project.cfg
else
    # If the config folder contains a project.cfg file, read the value after = from the config file
    projects_path=$(cat $AG_CONFIG_PATH/project.cfg | grep projects_path | sed 's/projects_path=//g')
    echo "projects_path = $projects_path"
fi

# functions

function setupVirtenv() {
    TARGET_PROJECT_PATH=$1
    REQUIREMENTS="gcc7 glibc ninja meson"
    echo "TARGET_PROJECT_PATH: $TARGET_PROJECT_PATH"
    cd $TARGET_PROJECT_PATH
    # Check if python3 virtual environment is installed
    if [ ! -d venv ]; then
        python3 -m venv venv
        source venv/bin/activate
        pip install $REQUIREMENTS
    fi
    cd $PWD
}

function checkProjectStatus() {
    TARGET_PROJECT_PATH=$1
    cd $TARGET_PROJECT_PATH
    echo "TARGET_PROJECT_PATH = $TARGET_PROJECT_PATH"
    # Get the list of all repos
    echo "Getting list of repos..."
    repos=$(find -L $TARGET_PROJECT_PATH -type d -name ".git" -o -type l -name ".git" -not -path "$TARGET_PROJECT_PATH/out/*")
    # repos=$(find $TARGET_PROJECT_PATH -type d -name ".git")

    # Create a variable to store repos that need to be pushed
    repos_to_push=""
    repos_array=()

    # Get the current projects manifest file and save it to a temp folder
    echo "Getting current projects manifest..."
    manifest=$(repo manifest -o $TEMP_PATH/manifest.xml)

    # Also get a revisional manifest for top commit ID
    echo "Generating revisional manifest. Please wait..."
    revisional_manifest=$(repo manifest -o $TEMP_PATH/revisional_manifest.xml -r)
    
    # Get the current date and time
    current_date=$(date +"%Y%m%d%H%M%S")
    # Save $repos_to_push to a file and show the user using alert_dialog
    echo "$TARGET_PROJECT_PATH" >$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
    # For each repo
    for repo in $repos; do

        # Change directory to the repo
        cd $repo

        # Get the current remote and branch
        current_remote=$(git remote show -n 1)
        current_branch=$(git branch | sed -n '1p')

        # get the path of $repo relative to $TARGET_PROJECT_PATH
        prefix="$TARGET_PROJECT_PATH/"
        suffix="/.git"
        string="$repo"
        repo_path=${string#"$prefix"}
        repo_path=${repo_path%"$suffix"}

        # check the $TEMP_PATH/manifest.xml for the line containing $repo_path
        # and if it does not exist, add it to $repos_to_push
        isInFile=$(echo "$manifest" | grep -c "$repo_path")

        if [ $isInFile -ne 0 ]; then
            echo "Project not found in manifest.xml: $repo_path"
            # repos_to_push="$repos_to_push $repo"
            echo "NOT IN MANIFEST: $repo_path" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
            # Get current revision using git branch --show-current
            revision=$(git --work-tree=$repo branch --show-current)
            # echo "revision: $revision"
        else
            # echo "repo_path already exists in manifest.xml"

            # check for uncommitted changes
            base_repo_path=${repo%"$suffix"}
            uncommitted_changes=$(git --work-tree=$base_repo_path status --porcelain | grep -c "M ")
            if [[ "$uncommitted_changes" != "" ]] && [[ "$uncommitted_changes" -ne 0 ]] && [[ "$uncommitted_changes" != "nothing to commit, working tree clean" ]]; then 
                echo "repo_path: $repo_path"
                echo "repo has uncommitted changes"
                echo "UNCOMMITTED CHANGES: $uncommitted_changes : $repo_path" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
                open_git_changes=$(git status)
                echo "      $open_git_changes" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
            fi

            # use git log to get the top commit ID
            top_commit_id=$(git --work-tree=$base_repo_path log -n 1 --pretty=format:%H)
            # echo "top_commit_id: $top_commit_id"
            short_commit_id=$(echo ${top_commit_id:0:10})
            
            # Check if the top commit ID matches up with the revisional_manifest for this repo
            rv_revision_pre=$(cat $TEMP_PATH/revisional_manifest.xml | grep "$repo_path")
            rv_revision_post=$(echo "$rv_revision_pre" | grep -o -P '(?<=revision=")[^"]+')
            short_rev_post=$(echo ${rv_revision_post:0:10})
            

            if [[ "$short_commit_id" != "$short_rev_post" ]] && [[ ! ${#top_commit_id} -gt 25 ]] && [[ "$short_commit_id" != "" ]] && [[ "$short_rev_post" != "" ]] ; then
                echo "repo_path: $repo_path"
                echo "short_commit_id: $short_commit_id"
                echo "short_rev_post: $short_rev_post"
                echo "Repo is checked out at a different place than in the manifest: $repo_path"
                echo "REVISION ID MISMATCH: $repo_path" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
            fi
            
            # Check if the top commit ID matches up with the revisional_manifest for this repo
            m_branch_pre=$(cat $TEMP_PATH/manifest.xml | grep "$repo_path")
            m_branch_post=$(echo "$m_branch_pre" | grep -o -P '(?<=revision=")[^"]+')
            # echo "m_branch_pre: $m_branch_pre"
            # echo "m_branch_post: $m_branch_post"

            # Get the repo remote URL using git remote show
            repo_remote=$(git remote show)
            if [ "$DEBUG" == "true" ]; then
                if [ "$repo_remote" == "" ]; then
                    echo "repo_remote: $repo_remote"
                fi
            fi

            git_remote_url=$(git remote get-url $repo_remote)
            if [ "$git_remote_url" == "" ]; then
                echo "Path is currently checked out at a different branch with no remote URL: $repo_path"
                echo "REPO CHECKED OUT AT DIFFERENT BRANCH: $repo_path" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
            fi

            # Get the repo branch name from git branch --show-current
            repo_branch=$(git --work-tree=$base_repo_path branch --show-current)
            # echo "repo_branch: $repo_branch"

            # Check the upstream remote has the current branched checked out at the same top_commit_id
            upstream_remote=$(git --work-tree=$base_repo_path ls-remote --heads $git_remote_url)
            upstream_commit_id=$(echo "$upstream_remote" | grep "refs/heads/$m_branch_post" | cut -f1)
            # echo "upstream_commit_id: $upstream_commit_id"

            if ! echo "$upstream_commit_id" | grep -q "$top_commit_id"; then
                echo "top_commit_id does not match upstream_commit_id"
                echo "repo_path: $repo_path"
                echo "TOP COMMIT ID DOES NOT MATCH UPSTREAM: $repo_path" >>$TARGET_PROJECT_PATH/repos_to_push-$current_date.txt
            fi

        fi

        cd $PWD
        
    done

    # If there are any repos that need to be pushed, display them and ask the user if they would like to push them
    if [[ $(cat $TARGET_PROJECT_PATH/repos_to_push-$current_date.txt | wc -l) -gt 0 ]]; then
        echo "The following repos need to be pushed:"
        cat $TARGET_PROJECT_PATH/repos_to_push-$current_date.txt | text

        # Ask the user if they would like to push the repos
        input 1 "Would you like to push the repos? (y/n) " "n"
        push_repos=$(0<"${dir_tmp}/${file_tmp}")

        # If the user says yes, push the repos
        if [[ $push_repos == "y" ]]; then
            for repo in $(cat $TARGET_PROJECT_PATH/repos_to_push-$current_date.txt); do
            cd $repo
            git push $current_remote $current_branch
            done
        fi
    fi

    # If the user wants to generate a manifest, generate it
    if [[ $push_repos == "y" ]]; then
        input 1 "Would you like to generate a manifest now? (y/n) " "n"
        generate_manifest=$(0<"${dir_tmp}/${file_tmp}")

        # If the user says yes, generate the manifest
        if [[ $generate_manifest == "y" ]]; then
            repo manifest -o $TARGET_PROJECT_PATH/manifest-$current_date.xml -r
        fi
    fi

}

function cloneAndroidGeneric() {

    TARGET_AG_PROJECT_PATH=$1

    if [[ ! -d $TARGET_AG_PROJECT_PATH/vendor/ag ]]; then
        # Ask the user if they would like to clone Android-Generic Project into their projects folder
        input 1 "Would you like to clone Android-Generic Project into your projects folder? (y/n)" "n"
        clone_answer=$(0<"${dir_tmp}/${file_tmp}")

        if [[ "$clone_answer" == "y" ]]; then
            # cd into the project folder
            cd $TARGET_AG_PROJECT_PATH
            echo "Current directory: $TARGET_AG_PROJECT_PATH"
            # clone in ag to vendor/ag
            git clone https://github.com/android-generic/vendor_ag vendor/ag
            cd $PWD
        else
            echo "Nothing to do. I guess we will have to part ways for now"
            exit 0
        fi
    else
        echo "Android-Generic Project already exists in your projects folder"
    fi


}

function deleteProject() {
    TARGET_AG_PROJECT_PATH=$1
    input 1 "Would you like to delete $TARGET_AG_PROJECT_PATH? (DELETE/n)" "n"
    DELETE_PROJECT_ANSWER=$(0<"${dir_tmp}/${file_tmp}")
    if [[ $DELETE_PROJECT_ANSWER == "DELETE" ]]; then
        rm -rf $TARGET_AG_PROJECT_PATH
    fi

}

function updateProject() {
    TARGET_AG_PROJECT_PATH=$1
    cd $TARGET_AG_PROJECT_PATH
    input 1 "Do you want to Force updates of $TARGET_AG_PROJECT_PATH? \n(WARNING: This will force updates and any unpushed changes will be lost). (y/n)" "n"
    REPO_SYNC_ANSWER=$(0<"${dir_tmp}/${file_tmp}")
    if [[ $REPO_SYNC_ANSWER == "y" ]]; then
        repo sync --force-sync
    else
        repo sync
    fi
}

function resetAgProjects() {
    input 1 "Would you like to reset the AG Project folder? (y/n)" "n"
    RESET_AG_CONFIG_ANSWER=$(0<"${dir_tmp}/${file_tmp}")
    if [[ $RESET_AG_CONFIG_ANSWER == "y" ]]; then
        rm -rf $AG_CONFIG_PATH/*
    else
        echo "Nothing to do. I guess we will have to part ways for now"
        exit 0
    fi
}

function pickNewProjectFolder() {
    message "Please enter the location of your projects folder: "
    dselect 
    projects_path=$(0<"${dir_tmp}/${file_tmp}")
    echo "projects_path = $projects_path"
    echo "projects_path=$projects_path" >>$AG_CONFIG_PATH/project.cfg
    # If the config folder contains a project.cfg file, read the value after = from the config file
    # projects_path=$(cat $AG_CONFIG_PATH/project.cfg | grep projects_path | sed 's/projects_path=//g')
}

# Repo fork functions
function getMatchingRepos() {
    local manifest_file=$1
    local specified_remote=$2
    local matching_repos=""

    while IFS= read -r line; do
        repo_path=$(echo $line | awk -F 'path="' '{print $2}' | awk -F '"' '{print $1}')
        remote_url=$(echo $line | awk -F "$specified_remote" '{print $2}' | awk -F '"' '{print $3}')

        if [[ "$remote_url" == *"$specified_remote"* ]]; then
            matching_repos="$matching_repos $repo_path"
        fi
    done < $manifest_file

    echo "$matching_repos"
}

function displayRepos() {
    local repos=$1

    echo "Repositories that match the specified remote:"
    echo "$repos"
}

function askConfirmation() {
    read -p "Do you want to proceed with creating forks? (y/n): " answer
    echo "$answer"
}

function checkRepoExists() {
    local target_org=$1
    local repo_path=$2

    existing_repo=$(curl -s "https://api.github.com/orgs/$target_org/repos?per_page=100&page=1" | jq -r --arg repo "$target_org/$repo_path" '.[] | select(.full_name == $repo)')

    if [[ -z "$existing_repo" ]]; then
        return 1
    else
        return 0
    fi
}

function createRepo() {
    local target_org=$1
    local repo_path=$2

    create_repo_response=$(curl -s -u "$GITHUB_USERNAME:$GITHUB_TOKEN" -X POST "https://api.github.com/orgs/$target_org/repos" -d "{\"name\":\"$repo_path\",\"private\":true}")

    if [[ $(echo $create_repo_response | jq -r '.name') == "$repo_path" ]]; then
        echo "New repository created: $target_org/$repo_path"
        return 0
    else
        echo "Failed to create repository: $target_org/$repo_path"
        return 1
    fi
}

function createFork() {
    local target_org=$1
    local repo_path=$2

    fork_response=$(curl -s -u "$GITHUB_USERNAME:$GITHUB_TOKEN" -X POST "https://api.github.com/repos/$target_org/$repo_path/forks")

    if [[ $(echo $fork_response | jq -r '.name') == "$repo_path" ]]; then
        echo "Fork created: $target_org/$repo_path"
        return 0
    else
        echo "Failed to create fork: $target_org/$repo_path"
        return 1
    fi
}

function createForks() {
    # Usage: createForks TARGET_PROJECT_PATH TARGET_ORG SPECIFIED_REMOTE
    TARGET_PROJECT_PATH=$1
    TARGET_ORG=$2
    SPECIFIED_REMOTE=$3

    cd $TARGET_PROJECT_PATH
    echo "TARGET_PROJECT_PATH = $TARGET_PROJECT_PATH"
    echo "Getting current projects manifest..."
    manifest=$(repo manifest -o $TEMP_PATH/manifest.xml)

    matching_repos=$(getMatchingRepos $TEMP_PATH/manifest.xml $SPECIFIED_REMOTE)
    displayRepos "$matching_repos"

    answer=$(askConfirmation)
    if [[ "$answer" != "y" ]] && [[ "$answer" != "Y" ]]; then
        echo "Aborting fork creation."
        return
    fi

    for repo_path in $matching_repos; do
        if checkRepoExists $TARGET_ORG $repo_path; then
            echo "Repository found in the target organization: $TARGET_ORG/$repo_path"
        else
            echo "Repository not found in the target organization: $TARGET_ORG/$repo_path"

            read -p "Do you want to create a new repo for $TARGET_ORG/$repo_path? (y/n): " create_repo_answer
            if [[ "$create_repo_answer" != "y" ]] && [[ "$create_repo_answer" != "Y" ]]; then
                echo "Skipping fork creation for $TARGET_ORG/$repo_path."
                continue
            fi

            if createRepo $TARGET_ORG $repo_path; then
                echo "New repository created: $TARGET_ORG/$repo_path"
            else
                echo "Failed to create repository: $TARGET_ORG/$repo_path"
                continue
            fi
        fi

        if createFork $TARGET_ORG $repo_path; then
            echo "Fork created: $TARGET_ORG/$repo_path"
        else
            echo "Failed to create fork: $TARGET_ORG/$repo_path"
        fi
    done
}



# main

# Find all subfolders in the projects folder
subfolders_list=$(find $projects_path -maxdepth 1 -mindepth 1 -type d)
echo "subfolders_list = $subfolders_list"

# Save the list of subfolders to a new variable in the "projects.list" file.
echo "$subfolders_list" >$AG_CONFIG_PATH/projects.list

# Build a list of menu items
main_menu_items=("Initialize Supported Project" \
    "Create New" "Setup Virtual Environment" \
    "Check Project Status" \
    "Add AG To Project" \
    "Update Project" \
    "Delete Project" \
    "Pick New Project Folder" \
    "Create Forks" \
    "Exit"
)

# present the list as a menu, with a Create New option added.
menu "$subfolders_list" "${main_menu_items[@]}"
projects_answer=$(0<"${dir_tmp}/${file_tmp}")

if [[ "$projects_answer" == "Initialize Supported Project" ]]; then
    # Check $SCRIPT_PATH/projects/api-* to see what api's are supported
    # Here is a table of the Android versions and their corresponding API levels:

    # echo api versions to text function using EOF
    echo "We need to start off by selecting an Android version using the API level
    Android Version | API Level
    ---             |---
    Android 13      | 33
    Android 12.1    | 32
    Android 12      | 31
    Android 11      | 30
    Android 10      | 29
    Android 9       | 28

    Select OK to continue
    " | text
    api_levels=$(find $SCRIPT_PATH/projects/ -maxdepth 1 -mindepth 1 -type d | cut -d '-' -f 4 | sort | uniq)
    echo "api_levels = $api_levels"
    menu "$api_levels"
    api_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$api_answer" == 0 ]]; then
        echo "$api_answer is not a valid API level"
        exit 1
    fi

    # find all *.prj files in the $SCRIPT_PATH/projects/$api_answer/ folder and make a list of those projects
    eligible_project_files=$(find $SCRIPT_PATH/projects/api-$api_answer -maxdepth 1 -mindepth 1 -type f -name "*.prj")
    eligible_private_project_files=$(find $SCRIPT_PATH/private_projects/api-$api_answer -maxdepth 1 -mindepth 1 -type f -name "*.prj")
    echo "eligible_project_files = $eligible_project_files"
    echo "eligible_private_project_files = $eligible_private_project_files"

    eligible_project_files="$eligible_project_files $eligible_private_project_files"
    
    # read each of the $eligible_project_files files and create a menu entry for each project using the
    # TIITLE="*" value inside the file
    project_titles=()
    for project_file in $eligible_project_files; do
        while read -r line; do
            if [[ "$line" == *"TIITLE"* ]]; then
                echo "line = $line"
                project_pre_title=$(echo "$line" | sed 's/TIITLE=//g')
                echo "project_pre_title = $project_pre_title"
                # Add new element at the end of the array
                project_titles+=("$project_pre_title")
            fi
        done < "$project_file"
    done
    echo """project_titles = "${project_titles[@]}""""
    info "Please choose from the following supported projects: "
    menu ${project_titles[@]}
    project_title_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_title_answer" == 0 ]]; then
        echo "$project_title_answer is not a valid project title"
        exit 1
    fi
    for project_file in $eligible_project_files; do
        seleced_project="false"
        while read -r line; do
            if [[ "$line" == *"TIITLE"* ]]; then
                selected_project_pre_title=$(echo "$line" | sed 's/TIITLE=//g'|tr -d '\n\t\r ' | tr -d '"')
                echo "selected_project_pre_title: $selected_project_pre_title"
                selected_project_title_answer=$(echo "$project_title_answer"|tr -d '\n\t\r ')
                echo "selected_project_title_answer: $selected_project_title_answer"
                if [[ "$selected_project_pre_title" == "$selected_project_title_answer" ]]; then
                    seleced_project="true"
                fi
            fi
            echo "seleced_project: $seleced_project"
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"MANIFEST_URL"* ]]; then
                project_manifest_url=$(echo "$line" | sed 's/MANIFEST_URL=//g')
                echo "project_manifest_url: $project_manifest_url"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"MANIFEST_BRANCH"* ]]; then
                project_manifest_branch=$(echo "$line" | sed 's/MANIFEST_BRANCH=//g')
                echo "project_manifest_branch: $project_manifest_branch"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"REQUIRES_AG"* ]]; then
                project_requires_ag=$(echo "$line" | sed 's/REQUIRES_AG=//g')
                echo "project_requires_ag: $project_requires_ag"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"GIT_LFS"* ]]; then
                project_git_lfs=$(echo "$line" | sed 's/GIT_LFS=//g')
                echo "project_git_lfs: $project_git_lfs"
            fi
            if [[ "$seleced_project" == "true" ]] && [[ "$line" == *"DEPENDENCIES"* ]]; then
                project_dependencies=$(echo "$line" | sed 's/DEPENDENCIES=//g')
                echo "project_dependencies: $project_dependencies"
            fi
        done < "$project_file"

        
    done

    # check through the project_dependencies and verify that the package is installed on the host
    installed_apps=$(apt list --installed)
    needs_to_install_list=()
    for app in $project_dependencies; do

        if [[ ! $(echo $installed_apps | grep "$app") ]]; then
            echo "Package $app is not installed on the host."
            needs_to_install_list+=("$app")
        fi
    done

    if [[ ${#needs_to_install_list[@]} -gt 0 ]]; then
        info "Missing apps: ${needs_to_install_list[@]}"
        menu "Install all missing dependencies" "Cancel"
        dependencies_answer=$(0<"${dir_tmp}/${file_tmp}")
        if [[ "$dependencies_answer" == "Install all missing dependencies" ]]; then
            for app in ${needs_to_install_list[@]}; do
                sudo apt install -y $app
            done
        else
            echo "Cancelled"
            exit
        fi
    else
        echo "All dependencies are installed"
    fi

    # ask the user what they would like to name their new project folder
    input 1 "Please enter the name of your new project folder: " "eg: my_project"
    project_name=$(0<"${dir_tmp}/${file_tmp}")

    # create new project folder in the user specified location
    mkdir -p "$projects_path/$project_name"

    # cd into that folder and use the $project_manifest_url and $project_manifest_branch variables to repo init
    cd $projects_path/$project_name
    echo "moving to path: $projects_path/$project_name"

    # repo init
    project_manifest_url=$(echo "$project_manifest_url"| tr -d '"')
    echo "project_manifest_url = $project_manifest_url"
    project_manifest_branch=$(echo "$project_manifest_branch"| tr -d '"')
    echo "project_manifest_branch = $project_manifest_branch"
    if [[ "$project_git_lfs" == "true" ]]; then
        repo init -u $project_manifest_url -b $project_manifest_branch --git-lfs
    else
        repo init -u $project_manifest_url -b $project_manifest_branch
    fi
    info "repo init done, now continuing onto the initial sync"
    repo sync
    cd $PWD
    # Save the current_project_folder to the config file
    echo "current_project_folder = $project_name" >>$AG_CONFIG_PATH/project.cfg
elif [[ "$projects_answer" == "Create New" ]]; then
    # we need to collect all the variables needed for the .prj file
    # this is done by using the variable names in the .prj file as the keys and their values as the values

    # Ask the new project name to be created
    input 1 "Please enter the name of your new project folder (no spaces): " "project_name"
    project_name=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_name" == 0 ]]; then
        alert_message "invalid project_name"
        exit 1
    fi
    # Ask the user for the project title, for TIITLE="*"
    input 1 "Please enter the title of your new project: " "project_title"
    project_title=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_title" == 0 ]]; then
        alert_message "invalid project_title"
        exit 1
    fi

    # ask the user for their project version, for VERSION="*"
    input 1 "Please enter the version of your new project: " "0.0"
    project_version=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_version" == 0 ]]; then
        alert_message "invalid project_version"
        exit 1
    fi

    # Ask the user for a project descrtion, for DESCRIPTION="*"
    input 1 "Please enter the description of your new project: " "project_description"
    project_description=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_description" == 0 ]]; then
        alert_message "invalid project_description"
        exit 1
    fi

    # Ask the user for the project dependencies, for DEPENDENCIES="*"
    input 1 "Please enter the dependencies of your new project: " "project_dependencies"
    project_dependencies=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_dependencies" == 0 ]]; then
        alert_message "invalid project_dependencies"
        exit 1
    fi

    # Ask the user for the project manifest url, for MANIFEST_URL="*"
    input 1 "Please enter the manifest url of your new project: " "project_manifest_url"
    project_manifest_url=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_manifest_url" == 0 ]]; then
        alert_message "invalid project_manifest_url"
        exit 1
    fi

    # Ask the user for the project manifest branch, for MANIFEST_BRANCH="*"
    input 1 "Please enter the manifest branch of your new project: " "project_manifest_branch"
    project_manifest_branch=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_manifest_branch" == 0 ]]; then
        alert_message "invalid project_manifest_branch"
        exit 1
    fi

    # Ask the user if this project requires Android-Generic for building, for REQUIRES_AG="*"
    input 1 "Please enter if this project requires Android-Generic for building (true/false): " "false"
    project_requires_ag=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_requires_ag" == 0 ]]; then
        alert_message "invalid project_requires_ag"
        exit 1
    fi

    # Ask the user if this project requires GIT LFS for building, for GIT_LFS="*"
    input 1 "Please enter if this project requires GIT LFS for building (true/false): " "false"
    project_git_lfs=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_git_lfs" == 0 ]]; then
        alert_message "invalid project_git_lfs"
        exit 1
    fi

    # Ask the user the target API for this project, for our folder creation
    input 1 "Please enter the target API level for this project:" "32"
    project_target_api=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$project_target_api" == 0 ]]; then
        alert_message "invalid project_target_api"
        exit 1
    fi

    echo "Creating $project_name.prj"

    # Check to make sure $SCRIPT_PATH/projects/api-$project_target_api exists
    if [[ ! -d $SCRIPT_PATH/projects/api-$project_target_api ]]; then
        mkdir -p $SCRIPT_PATH/projects/api-$project_target_api
    fi

    # Create the $project_name.prj file, and save it as $SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "TITLE=$project_title" >$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "VERSION=$project_version" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "DESCRIPTION=$project_description" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "DEPENDENCIES=$project_dependencies" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "MANIFEST_URL=$project_manifest_url" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "MANIFEST_BRANCH=$project_manifest_branch" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "REQUIRES_AG=$project_requires_ag" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj
    echo "GIT_LFS=$project_git_lfs" >>$SCRIPT_PATH/projects/api-$project_target_api/$project_name.prj

    ok_message "$project_name.prj created in $SCRIPT_PATH/projects/api-$project_target_api \nYou will be given the option to commit your changes when complete."

    # Save the current_project_folder to the config file
    echo "current_project_folder = $project_name" >>$AG_CONFIG_PATH/project.cfg

    # create new project folder in the user specified location
    mkdir -p $projects_path/$project_name
    cd $projects_path/$project_name

    echo "Running repo init for that project now"
    if [[ "$project_git_lfs" == "true" ]]; then
        repo init -u $project_manifest_url -b $project_manifest_branch --git-lfs
    else
        repo init -u $project_manifest_url -b $project_manifest_branch
    fi

    echo "Running repo sync for that project now"
    # run repo sync command in the terminal window to show progress
    repo sync --force-sync -c
elif [[ "$projects_answer" == "Setup Virtual Environment" ]]; then
    # Select what project to setup the setupVirtenv() function for
    info "Please select which project to setup the virtual environment for"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    setupVirtenv $current_project_folder
elif [[ "$projects_answer" == "Check Project Status" ]]; then
    # Select what project to check the checkProjectStatus() function for
    info "Please select which project to check the project status for"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    checkProjectStatus $current_project_folder
elif [[ "$projects_answer" == "Delete Project" ]]; then
    # Select what project to delete the deleteProject() function for
    info "Please select which project to delete"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    deleteProject $current_project_folder
elif [[ "$projects_answer" == "Update Project" ]]; then
    # Select what project to update the updateProject() function for
    info "Please select which project to update"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    updateProject $current_project_folder
elif [[ "$projects_answer" == "Add AG To Project" ]]; then
    # Select what project to add the cloneAndroidGeneric() function for
    info "Please select which project to add AG to"
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    echo "current_project_folder = $current_project_folder"
    cloneAndroidGeneric $current_project_folder
elif [[ "$projects_answer" == "Pick New Project Folder" ]]; then
    # Clears the Project Folder preferences and exits the script
    resetAgProjects
    pickNewProjectFolder
    alert_message "Project Folder Reset Complete \nRelaunch the program to continue"
    exit 0
elif [[ "$projects_answer" == "Create Forks" ]]; then
    # createForks TARGET_PROJECT_PATH TARGET_ORG SPECIFIED_REMOTE
    #
    # Define the TARGET_PROJECT_PATH
    dselect "$projects_path"
    current_project_folder=$(0<"${dir_tmp}/${file_tmp}")
    # Define the TARGET_ORG
    input 1 " Please enter the ssh address of the target org: " "ssh://git@github.com/target-org"
    target_org=$(0<"${dir_tmp}/${file_tmp}")
    echo "target_org = $target_org"

    # Define the SPECIFIED_REMOTE
    #
    # Get all remotes from current_project_folder manifest
    remote_names=()
    remote_urls=()
    remote_menu_options=()
    # cd into current_project_folder/.repo/manifests and grep for "<remote name=", 
    # then save the remote_name to the "name=" and remote_url to the "fetch=" value
    cd $current_project_folder/.repo/manifests
    for remote in $(grep "<remote name=" $current_project_folder/.repo/manifests/manifest.xml | awk -F'>' '{print $2}' | awk -F'<' '{print $1}'); do
        remote_names+=($remote)
        remote_urls+=($remote)
        # Now we combine both names and urls to make a menu option
        remote_menu_options+=($remote_names[-1] $remote_urls[-1])
    done
    menu "$remote_menu_options"
    remote_answer=$(0<"${dir_tmp}/${file_tmp}")
    # cut the remote_answer to be just the name
    remote_name=$(0<"${dir_tmp}/${file_tmp}")
    echo "remote_name = $remote_name"
    remote_url=$(0<"${dir_tmp}/${file_tmp}")
    echo "remote_url = $remote_url"

    createForks $current_project_folder $target_org $remote_name
    
elif [[ "$projects_answer" == "Exit" ]]; then
    exit 0
elif [[ -d "$projects_answer" ]]; then
    # cd into the $projects_answer folder and set this as the current_project_folder variable
    cd $projects_answer
    current_project_folder=$projects_answer
    # Save the current_project_folder to the config file
    echo "current_project_folder = $current_project_folder" >>$AG_CONFIG_PATH/project.cfg
    cd $PWD
else 
    echo "not a valid selection"
    exit 0
fi

# Ask if this project requires Android-Generic
if [[ "$project_requires_ag" == "true" ]]; then
    echo "This project requires Android-Generic to be cloned thio the project folder in order to build Android-x86 (PC)" | text 
    cloneAndroidGeneric
fi

if [[ -d $current_project_folder/vendor/ag ]]; then

    # Ask if they would like to launch the AG menu option
    input 1 "Would you like to launch the Android-Generic Project Menu? (y/n)" "y"
    ag_menu_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$ag_menu_answer" == "y" ]]; then
        cd $current_project_folder
        . build/envsetup.sh
        if [[ -f $current_project_folder/vendor/ag/ag-menu-new.sh ]]; then
            ag-menu
        else
            # Old version requires us to specify a target type (pc, gsi, emu)
            # We will just choose pc for now
            ag-menu pc 
        fi
    fi
fi

# cd into the $SCRIPT_PATH
cd $SCRIPT_PATH

# Use git status to see if $SCRIPT_PATH has any changes that need to be committed
needs_updating=$(git status --porcelain)
if [[ "$needs_updating" != "" ]]; then
    # Ask the user if they would like to commit the changes
    input 1 "Would you like to commit the changes in $SCRIPT_PATH? (y/n)" "n"
    commit_answer=$(0<"${dir_tmp}/${file_tmp}")
    if [[ "$commit_answer" == "y" ]]; then
        git add .
        git commit -m "Project $current_project_folder updated"
        info "Project $current_project_folder updated, please consider submitting your changes in a pull-request"
    else
        info "Project $current_project_folder not updated"
    fi
fi
