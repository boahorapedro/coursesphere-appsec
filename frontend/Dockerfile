# Use an official Node.js image as the base
FROM node:20-alpine

# Set the working directory inside the container
WORKDIR /app

# Copy package.json and package-lock.json to the working directory
COPY package*.json ./

# Install dependencies
RUN npm install
RUN npm install -g serve

# Copy the rest of the app's source code to the working directory
COPY . .

# Build the app
RUN npx vite build

# Expose the port that the app will run on
EXPOSE 3000

# Switch to a non-root user for security
USER node

# Define the command to run the app
CMD ["serve", "-s", "dist", "-l", "3000"]
