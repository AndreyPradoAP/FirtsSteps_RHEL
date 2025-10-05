#!/bin/bash

dnf update

read -r -p "Quer criar um usuário para o sistema (S/n)? " resposta

while [ "$resposta" = "S" ];
do
	# Criação de usuário sudoers
	read -r -p "Digite o nome do novo usuário: " nomeUser
	useradd $nomeUser
	# Adicionar uma forma de verificar se o usuário foi criado
	echo "Usuário criado. Digite uma senha para ele"
	passwd $nomeUser
	usermod -aG wheel $nomeUser

	read -r -p "Criar um novo usuário (S/n)? " resposta
done
