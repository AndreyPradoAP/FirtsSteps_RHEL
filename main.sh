#!/bin/bash

dnf update

read -r -p "Quer criar um usuário para o sistema (S/n)? " $resposta

while [ "$resposta" = "S" ];
do
	read -r -p "Digite o nome do novo usuário: " $nomeUser
	useradd $nomeUser

	
done
