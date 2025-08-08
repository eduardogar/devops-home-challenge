#!/bin/bash

# A simple script to start the Minikube cluster with the specified configuration.
# This script first checks if Minikube is already running, then starts it if needed.

echo "Checking for existing 'devops-challenge' Minikube cluster..."
if minikube status --profile=devops-challenge &> /dev/null; then
  echo "Minikube cluster 'devops-challenge' is already running. Skipping start."
else
  echo "Starting new 'devops-challenge' Minikube cluster..."
  minikube start --profile=devops-challenge --driver=docker --kubernetes-version=v1.28.3 --memory=6144 --cpus=4 --v=9

  # You can add more commands here to check status after startup
  if [ $? -eq 0 ]; then
    echo "Minikube started successfully."
  else
    echo "Minikube failed to start. Please check the logs above for details."
  fi
fi

# Example of how you could check the status of the cluster after running the script
minikube status --profile=devops-challenge
